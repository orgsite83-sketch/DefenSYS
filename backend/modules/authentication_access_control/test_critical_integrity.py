"""Regressions for private file access and destructive read/roster paths."""

from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.test import override_settings
from django.urls import reverse
from rest_framework.exceptions import ValidationError
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from student_teams.documents.models import TeamDocument
from student_teams.models import StudentTeam, TeamMembership
from student_teams.serializers import StudentTeamWriteSerializer


class CriticalIntegrityTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        users = get_user_model().objects
        cls.admin = users.create_user(username='integrity-admin', role='admin')
        cls.owner = users.create_user(username='integrity-owner', role='student')
        cls.outsider = users.create_user(username='integrity-outsider', role='student')
        cls.adviser = users.create_user(username='integrity-adviser', role='faculty', is_adviser=True)
        year = SchoolYear.objects.create(label='2026-2027')
        cls.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        cls.team = StudentTeam.objects.create(
            name='Integrity Team', project_title='Integrity Project',
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year',
            semester=cls.semester, leader=cls.owner, adviser=cls.adviser,
            current_defense_stage='Integrity Stage',
        )
        cls.membership = TeamMembership.objects.create(team=cls.team, student=cls.owner, is_leader=True)
        cls.stage = DefenseStage.objects.create(label='Integrity Stage')
        cls.definition = StageDeliverable.objects.create(
            defense_stage=cls.stage, deliverable_id='INT1', label='Private draft',
            deliverable_type='pre', is_defense_material=True,
        )

    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        settings_override = override_settings(
            MEDIA_ROOT=directory.name,
            STORAGES={'default': {
                'BACKEND': 'django.core.files.storage.FileSystemStorage',
                'OPTIONS': {'location': directory.name, 'base_url': '/media/'},
            }},
        )
        settings_override.enable()
        self.addCleanup(settings_override.disable)
        self.submission = DeliverableSubmission.objects.create(
            team=self.team, stage_label=self.stage.label, deliverable_id='INT1',
            label='Private draft', deliverable_type='pre', uploaded_by=self.owner,
        )
        self.file = DeliverableSubmissionFile.objects.create(
            submission=self.submission, file_name='private.txt', extracted_text='fixture',
            file=ContentFile(b'private student work', name='private.txt'),
        )

    def fetch(self, user, name=None, *, legacy=False):
        self.client.force_authenticate(user=user)
        name = name or self.file.file.name
        path = '/media/' + name if legacy else reverse('media_file_serve', kwargs={'file_path': name})
        response = self.client.get(path)
        if response.streaming:
            with default_storage.open(name, 'rb') as stored:
                self.assertEqual(b''.join(response.streaming_content), stored.read())
        return response

    def test_private_deliverable_owner_adviser_admin_and_outsider(self):
        for user in (self.owner, self.adviser, self.admin):
            with self.subTest(user=user.username):
                self.assertEqual(self.fetch(user).status_code, 200)
        self.assertEqual(self.fetch(self.outsider).status_code, 404)

    def test_legacy_media_path_enforces_the_same_access_in_debug_mode(self):
        with override_settings(DEBUG=True):
            self.assertEqual(self.fetch(None, legacy=True).status_code, 401)
            self.assertEqual(self.fetch(self.outsider, legacy=True).status_code, 404)
            self.assertEqual(self.fetch(self.owner, legacy=True).status_code, 200)

    def test_unknown_storage_file_is_not_downloadable_even_by_admin(self):
        name = default_storage.save('unregistered.txt', ContentFile(b'not an application record'))
        self.assertEqual(self.fetch(self.admin, name).status_code, 404)

    def test_django_admin_session_can_open_its_file_links(self):
        self.client.force_login(self.admin)
        response = self.client.get('/media/' + self.file.file.name)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'private student work')

    def test_accepted_unrestricted_archive_is_still_shared(self):
        self.submission.deliverable_type = 'post'
        self.submission.status = DeliverableSubmission.STATUS_ACCEPTED
        self.submission.save()
        self.assertEqual(self.fetch(self.outsider).status_code, 200)
        self.definition.is_restricted = True
        self.definition.save()
        self.assertEqual(self.fetch(self.outsider).status_code, 404)
        self.assertEqual(self.fetch(self.owner).status_code, 200)

    def test_team_document_requires_team_access(self):
        document = TeamDocument.objects.create(
            team=self.team, uploaded_by=self.owner, file_name='team.txt',
            file_size=4, mime_type='text/plain', file=ContentFile(b'team', name='team.txt'),
        )
        self.assertEqual(self.fetch(self.owner, document.file.name).status_code, 200)
        self.assertEqual(self.fetch(self.outsider, document.file.name).status_code, 404)

    def test_signature_is_private_but_avatar_remains_public(self):
        self.owner.e_signature.save('signature.png', ContentFile(b'signature'))
        self.owner.avatar.save('avatar.png', ContentFile(b'avatar'))
        self.assertEqual(self.fetch(self.owner, self.owner.e_signature.name).status_code, 200)
        self.assertEqual(self.fetch(self.outsider, self.owner.e_signature.name).status_code, 404)
        self.assertEqual(self.fetch(None, self.owner.e_signature.name, legacy=True).status_code, 401)
        self.assertEqual(self.fetch(None, self.owner.avatar.name, legacy=True).status_code, 200)

    def test_panelist_can_read_only_assigned_defense_material(self):
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist

        panelist = get_user_model().objects.create_user(username='integrity-panelist', role='faculty')
        schedule = DefenseSchedule.objects.create(
            scope='capstone', semester=self.semester, team=self.team, defense_stage=self.stage,
            scheduled_date='2026-09-30', start_time='09:00', slot_duration=60, room='Integrity Room',
        )
        SchedulePanelist.objects.create(schedule=schedule, panelist=panelist)
        self.assertEqual(self.fetch(panelist).status_code, 200)
        self.definition.is_defense_material = False
        self.definition.save()
        self.assertEqual(self.fetch(panelist).status_code, 404)

    def test_archive_and_deliverable_gets_preserve_all_stored_files(self):
        second = DeliverableSubmissionFile.objects.create(
            submission=self.submission, file_name='newer.txt', extracted_text='fixture',
            file=ContentFile(b'newer work', name='newer.txt'),
        )
        self.client.force_authenticate(user=self.admin)
        original_ids = set(self.submission.files.values_list('id', flat=True))
        for route in ('capstone_deliverables', 'project_archive'):
            for _ in range(2):
                response = self.client.get(reverse(route))
                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(set(self.submission.files.values_list('id', flat=True)), original_ids)
                self.assertTrue(default_storage.exists(self.file.file.name))
                self.assertTrue(default_storage.exists(second.file.name))

    def test_guest_token_is_limited_to_active_assigned_defense_materials(self):
        from defense.scheduler.models import DefenseSchedule
        from rest_framework_simplejwt.tokens import AccessToken
        from user_management.models import GuestPanelistCode

        schedule = DefenseSchedule.objects.create(
            scope='capstone', semester=self.semester, team=self.team, defense_stage=self.stage,
            scheduled_date='2026-09-30', start_time='09:00', slot_duration=60, room='Guest Room',
        )
        code = GuestPanelistCode.objects.create(guest_name='Integrity Guest', defense_schedule=schedule)
        token = AccessToken()
        for key, value in {
            'guest_panelist': True, 'guest_code_id': code.pk, 'guest_code': code.code,
            'defense_schedule_id': schedule.pk, 'team_id': self.team.pk,
        }.items():
            token[key] = value
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        path = reverse('media_file_serve', kwargs={'file_path': self.file.file.name})
        response = self.client.get(path)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'private student work')
        self.definition.is_defense_material = False
        self.definition.save()
        self.assertEqual(self.client.get(path).status_code, 404)
        self.definition.is_defense_material = True
        self.definition.save()
        code.is_active = False
        code.save()
        self.assertEqual(self.client.get(path).status_code, 404)

    def test_weekly_report_owner_and_adviser_can_read_but_other_student_cannot(self):
        from student_teams.weekly_progress.models import WeeklyProgressReport

        report = WeeklyProgressReport.objects.create(
            team=self.team, student=self.owner, week_number=1, report_date='2026-09-30',
            extracted_text='fixture', report_file=ContentFile(b'progress', name='weekly.txt'),
        )
        TeamMembership.objects.create(team=self.team, student=self.outsider)
        self.assertEqual(self.fetch(self.owner, report.report_file.name).status_code, 200)
        self.assertEqual(self.fetch(self.adviser, report.report_file.name).status_code, 200)
        self.assertEqual(self.fetch(self.outsider, report.report_file.name).status_code, 404)

    def test_minutes_file_uses_schedule_view_permissions(self):
        from defense.minutes.models import DefenseMinutes
        from defense.scheduler.models import DefenseSchedule

        schedule = DefenseSchedule.objects.create(
            scope='capstone', semester=self.semester, team=self.team, defense_stage=self.stage,
            scheduled_date='2026-09-30', start_time='09:00', slot_duration=60, room='Minutes Room',
        )
        minutes = DefenseMinutes.objects.create(
            schedule=schedule, team_name=self.team.name, project_title=self.team.project_title,
            defense_stage_label=self.stage.label, defense_date='2026-09-30', defense_time='09:00',
            room='Minutes Room', pdf_file=ContentFile(b'minutes', name='minutes.pdf'),
        )
        self.assertEqual(self.fetch(self.adviser, minutes.pdf_file.name).status_code, 200)
        self.assertEqual(self.fetch(self.outsider, minutes.pdf_file.name).status_code, 404)

    def make_team(self, name, *, pit=False, event='Integrity Stage', semester=None):
        return StudentTeam.objects.create(
            name=name, project_title=name, leader=self.outsider,
            level=StudentTeam.LEVEL_3_PIT if pit else StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year', semester=semester or self.semester, current_defense_stage=event,
        )

    def test_conflict_at_save_preserves_both_team_rosters(self):
        other = self.make_team('Other Capstone')
        original = TeamMembership.objects.create(team=other, student=self.outsider, is_leader=True)
        with self.assertRaises(ValidationError):
            StudentTeamWriteSerializer()._sync_members(other, [self.owner.pk], self.owner.pk)
        self.assertTrue(TeamMembership.objects.filter(pk=self.membership.pk).exists())
        self.assertTrue(TeamMembership.objects.filter(pk=original.pk).exists())

    def test_create_rolls_back_if_membership_became_unavailable_after_validation(self):
        # Exercise the write boundary with data already accepted by validation.
        with self.assertRaises(ValidationError):
            StudentTeamWriteSerializer().create({
                'name': 'Rejected New Team', 'level': StudentTeam.LEVEL_3_CAPSTONE,
                'year_level': '3rd Year', 'semester': self.semester, 'leader': self.owner,
                'member_ids': [self.owner.pk],
            })
        self.assertFalse(StudentTeam.objects.filter(name='Rejected New Team').exists())
        self.assertTrue(TeamMembership.objects.filter(pk=self.membership.pk).exists())

    def test_update_rolls_back_team_changes_when_membership_conflicts(self):
        other = self.make_team('Unchanged Team')
        membership = TeamMembership.objects.create(team=other, student=self.outsider)
        with self.assertRaises(ValidationError):
            StudentTeamWriteSerializer().update(other, {
                'name': 'Rejected Rename', 'level': other.level, 'year_level': other.year_level,
                'semester': self.semester, 'leader': self.owner, 'member_ids': [self.owner.pk],
            })
        other.refresh_from_db()
        self.assertEqual(other.name, 'Unchanged Team')
        self.assertEqual(other.leader_id, self.outsider.pk)
        self.assertTrue(TeamMembership.objects.filter(pk=membership.pk).exists())
        self.assertTrue(TeamMembership.objects.filter(pk=self.membership.pk).exists())

    def test_pit_sync_preserves_capstone_membership_with_same_stage_name(self):
        pit = self.make_team('Same Label PIT', pit=True)
        StudentTeamWriteSerializer()._sync_members(pit, [self.owner.pk], self.owner.pk)
        self.assertTrue(TeamMembership.objects.filter(pk=self.membership.pk).exists())
        self.assertTrue(pit.memberships.filter(student=self.owner).exists())

    def test_pit_same_event_conflicts_but_other_events_are_preserved(self):
        first = self.make_team('PIT A', pit=True)
        second = self.make_team('PIT B', pit=True)
        membership = TeamMembership.objects.create(team=first, student=self.owner)
        serializer = StudentTeamWriteSerializer()
        with self.assertRaises(ValidationError):
            serializer._sync_members(second, [self.owner.pk], self.owner.pk)
        second.current_defense_stage = 'Different Event'
        second.save()
        serializer._sync_members(second, [self.owner.pk], self.owner.pk)
        self.assertTrue(TeamMembership.objects.filter(pk=membership.pk).exists())

    def test_null_pit_event_conflicts_without_deleting_members(self):
        first = self.make_team('Unassigned PIT A', pit=True, event=None)
        second = self.make_team('Unassigned PIT B', pit=True, event='')
        membership = TeamMembership.objects.create(team=first, student=self.owner)
        with self.assertRaises(ValidationError):
            StudentTeamWriteSerializer()._sync_members(second, [self.owner.pk], self.owner.pk)
        self.assertTrue(TeamMembership.objects.filter(pk=membership.pk).exists())

    def test_historical_membership_does_not_block_new_semester(self):
        semester = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        team = self.make_team('Next Semester Team', semester=semester)
        StudentTeamWriteSerializer()._sync_members(team, [self.owner.pk], self.owner.pk)
        self.assertTrue(TeamMembership.objects.filter(pk=self.membership.pk).exists())
        self.assertTrue(team.memberships.filter(student=self.owner).exists())
