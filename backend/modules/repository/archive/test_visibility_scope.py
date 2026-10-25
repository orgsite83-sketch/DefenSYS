"""Public visibility follows the owning definition when local IDs are reused."""
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventDeliverable, PitEventGradingConfig
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import StudentTeam

from .services import (
    capstone_restricted_queryset,
    capstone_visible_queryset,
    pit_restricted_queryset,
    pit_visible_deliverables_queryset,
)


class ArchiveVisibilityScopeTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.student = User.objects.create_user(username='library-reader', role='student')
        cls.admin = User.objects.create_user(username='library-admin', role='admin')
        year = SchoolYear.objects.create(label='2026-2027')
        cls.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        cls.other_semester = Semester.objects.create(school_year=year, label=Semester.SECOND)
        cls.public_event = PitEventGradingConfig.objects.create(
            semester=cls.semester, year_level='1st Year', event_name='System Concept Pitching',
        )
        cls.private_event = PitEventGradingConfig.objects.create(
            semester=cls.semester, year_level='2nd Year', event_name='PIT System Prototype Showcase',
        )
        for event, label, restricted in (
            (cls.public_event, 'Approved Concept Paper', False),
            (cls.private_event, 'Source Code', True),
        ):
            PitEventDeliverable.objects.create(
                pit_event_config=event, deliverable_id='D3', label=label,
                deliverable_type='post', is_restricted=restricted,
            )
        cls.public_submission = cls._submission(cls.public_event, 'Concept Paper')
        cls.private_submission = cls._submission(cls.private_event, 'Source Code')

    @classmethod
    def _submission(cls, event, name):
        team = StudentTeam.objects.create(
            name=f'Team {name}', project_title=name, semester=event.semester,
            year_level=event.year_level, leader=cls.student,
            level=StudentTeam.LEVEL_1_PIT if event.year_level == '1st Year' else StudentTeam.LEVEL_2_PIT,
        )
        return DeliverableSubmission.objects.create(
            team=team, stage_label=event.event_name, deliverable_id='D3', label=name,
            deliverable_type='post', status='accepted', file_name=f'{name}.pdf',
        )

    def _assert_pit_visibility(self):
        self.assertEqual(list(pit_visible_deliverables_queryset()), [self.public_submission])
        self.assertEqual(list(pit_restricted_queryset()), [self.private_submission])

    def test_reused_id_keeps_public_paper_visible_and_source_code_private(self):
        self._assert_pit_visibility()
        for user in (self.student, self.admin):
            self.client.force_authenticate(user)
            for url in ('/api/repository/archive/', '/api/repository/archive/search/'):
                with self.subTest(role=user.role, url=url):
                    response = self.client.get(url)
                    self.assertEqual(response.status_code, 200)
                    self.assertEqual(
                        [entry['source_id'] for entry in response.data['entries']],
                        [self.public_submission.pk],
                    )
                    self.assertEqual(response.data['counts']['pit'], 1)
                    self.assertEqual(response.data['counts']['restricted'], 1)
            response = self.client.get('/api/repository/archive/search/', {'search': 'Source Code'})
            self.assertEqual(response.data['entries'], [])

    def test_unrelated_student_file_access_uses_the_same_scoped_visibility(self):
        from defensys_backend.media_access import _can_read_submission
        reader = get_user_model().objects.create_user(username='unrelated-library-reader', role='student')
        self.assertTrue(_can_read_submission(reader, self.public_submission))
        self.assertFalse(_can_read_submission(reader, self.private_submission))

    def test_restrictions_are_local_to_event_cohort_and_term(self):
        for semester, year, name in (
            (self.semester, '1st Year', 'Another first-year event'),
            (self.other_semester, '1st Year', self.public_event.event_name),
        ):
            event = PitEventGradingConfig.objects.create(
                semester=semester, year_level=year, event_name=name,
            )
            PitEventDeliverable.objects.create(
                pit_event_config=event, deliverable_id='D3', label='Private output',
                deliverable_type='post', is_restricted=True,
            )
        self._assert_pit_visibility()

    def test_legacy_fallback_does_not_borrow_another_cohorts_restriction(self):
        DeliverableSubmission.objects.filter(pk=self.public_submission.pk).update(pit_event_config=None)
        PitEventGradingConfig.objects.filter(pk=self.public_event.pk).update(year_level='2nd Year')
        PitEventDeliverable.objects.filter(pit_event_config=self.public_event).update(is_restricted=True)
        self._assert_pit_visibility()

    def test_legacy_rows_without_event_reference_keep_captured_scope(self):
        DeliverableSubmission.objects.update(pit_event_config=None)
        # The current team no longer supplies the historical file's scope.
        StudentTeam.objects.filter(pk=self.public_submission.team_id).update(
            year_level='2nd Year', level=StudentTeam.LEVEL_2_PIT, semester=self.other_semester,
        )
        self._assert_pit_visibility()

    def test_legacy_rows_without_snapshots_use_the_original_team_scope(self):
        DeliverableSubmission.objects.update(
            pit_event_config=None, archive_semester=None, archive_year_level='',
        )
        self._assert_pit_visibility()

    def test_unclassified_legacy_event_remains_restricted(self):
        DeliverableSubmission.objects.filter(pk=self.private_submission.pk).update(pit_event_config=None)
        PitEventGradingConfig.objects.filter(pk=self.private_event.pk).update(year_level='')
        self._assert_pit_visibility()

    def test_restriction_changes_apply_only_to_the_owning_event(self):
        PitEventDeliverable.objects.filter(pit_event_config=self.public_event).update(is_restricted=True)
        self.assertFalse(pit_visible_deliverables_queryset().exists())
        self.assertEqual(pit_restricted_queryset().count(), 2)
        PitEventDeliverable.objects.filter(pit_event_config=self.private_event).update(is_restricted=False)
        self.assertEqual(list(pit_visible_deliverables_queryset()), [self.private_submission])
        self.assertEqual(list(pit_restricted_queryset()), [self.public_submission])

    def test_pending_and_pre_defense_submissions_stay_out_of_public_library(self):
        for field, value in (('status', 'pending'), ('deliverable_type', 'pre')):
            with self.subTest(field=field):
                DeliverableSubmission.objects.filter(pk=self.public_submission.pk).update(**{field: value})
                self.assertFalse(pit_visible_deliverables_queryset().exists())
                DeliverableSubmission.objects.filter(pk=self.public_submission.pk).update(
                    status='accepted', deliverable_type='post',
                )

    def test_capstone_restrictions_are_local_to_stage(self):
        team = StudentTeam.objects.create(
            name='Capstone library team', project_title='Capstone Project',
            semester=self.semester, year_level='4th Year', level=StudentTeam.LEVEL_4_CAPSTONE,
            leader=self.student,
        )
        submissions = []
        for label, restricted in (('Library Proposal', False), ('Library Final', True)):
            stage = DefenseStage.objects.create(label=label)
            StageDeliverable.objects.create(
                defense_stage=stage, deliverable_id='D3', label='Output',
                deliverable_type='post', is_restricted=restricted,
            )
            submissions.append(DeliverableSubmission.objects.create(
                team=team, stage_label=label, deliverable_id='D3', label='Output',
                deliverable_type='post', status='accepted', file_name=f'{label}.pdf',
            ))
        self.assertEqual(list(capstone_visible_queryset()), submissions[:1])
        self.assertEqual(list(capstone_restricted_queryset()), submissions[1:])
        # Restricted D3 definitions in either track cannot hide the other
        # track's public D3 output.
        self._assert_pit_visibility()
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/repository/archive/', {'type': 'capstone'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([entry['source_id'] for entry in response.data['entries']], [submissions[0].pk])

