from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam
from defense.minutes.models import DefenseMinutes, MinutesPanelistComment
from notifications.models import Notification

User = get_user_model()

class DocumenterDashboardApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.doc_faculty = User.objects.create_user(
            username='doc-faculty',
            password='pass12345',
            role='faculty',
            first_name='Marie',
            last_name='Curie',
            is_documenter=True,
        )
        self.non_doc_faculty = User.objects.create_user(
            username='non-doc-faculty',
            password='pass12345',
            role='faculty',
            first_name='Albert',
            last_name='Einstein',
            is_documenter=False,
        )
        self.student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )

        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        
        # Get or create stage
        self.stage, _ = DefenseStage.objects.get_or_create(label='Project Proposal')
        
        self.team = StudentTeam.objects.create(
            name='Team TestSync',
            project_title='Test Title',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.non_doc_faculty,
        )

        # Create a defense schedule assigned to doc_faculty
        self.schedule_assigned = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date='2026-06-30',
            start_time='09:00',
            slot_duration=60,
            room='Room 101',
            documenter=self.doc_faculty,
        )

        # Create another defense schedule not assigned to doc_faculty (assigned to admin/no one)
        self.schedule_other = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date='2026-06-30',
            start_time='10:00',
            slot_duration=60,
            room='Room 102',
            documenter=None,
        )

    def test_anonymous_user_unauthorized(self):
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_student_user_forbidden(self):
        self.client.force_authenticate(user=self.student)
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_non_documenter_faculty_empty_assignments(self):
        self.client.force_authenticate(user=self.non_doc_faculty)
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 0)

    def test_documenter_faculty_list_assignments_no_minutes(self):
        self.client.force_authenticate(user=self.doc_faculty)
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['id'], self.schedule_assigned.id)
        self.assertEqual(response.data[0]['minutes_status'], None)
        self.assertEqual(response.data[0]['minutes_id'], None)

    def test_documenter_faculty_list_assignments_with_minutes(self):
        # Create defense minutes for the schedule
        minutes = DefenseMinutes.objects.create(
            schedule=self.schedule_assigned,
            team_name=self.team.name,
            project_title=self.team.project_title,
            adviser_name='Albert Einstein',
            defense_stage_label=self.stage.label,
            defense_date='2026-06-30',
            defense_time='09:00:00',
            room='Room 101',
            documenter_name='Marie Curie',
            status=DefenseMinutes.STATUS_SUBMITTED,
        )
        self.client.force_authenticate(user=self.doc_faculty)
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['id'], self.schedule_assigned.id)
        self.assertEqual(response.data[0]['minutes_status'], 'submitted')
        self.assertEqual(response.data[0]['minutes_id'], minutes.id)


class MinutesCrudApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        
        # Simple GIF data to simulate an image file for e-signature
        small_gif = (
            b'\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x00\x00\x00\x21\xf9\x04'
            b'\x01\x0a\x00\x01\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02'
            b'\x02\x4c\x01\x00\x3b'
        )
        sig_file_doc = SimpleUploadedFile('sig_doc.gif', small_gif, content_type='image/gif')
        sig_file_adv = SimpleUploadedFile('sig_adv.gif', small_gif, content_type='image/gif')
        sig_file_admin = SimpleUploadedFile('sig_admin.gif', small_gif, content_type='image/gif')

        self.doc_faculty = User.objects.create_user(
            username='doc-faculty',
            password='pass12345',
            role='faculty',
            first_name='Marie',
            last_name='Curie',
            is_documenter=True,
            e_signature=sig_file_doc,
        )
        self.adviser_faculty = User.objects.create_user(
            username='adviser-faculty',
            password='pass12345',
            role='faculty',
            first_name='Albert',
            last_name='Einstein',
            is_documenter=False,
            e_signature=sig_file_adv,
        )
        self.panelist_1 = User.objects.create_user(
            username='panelist-1',
            password='pass12345',
            role='faculty',
            first_name='Isaac',
            last_name='Newton',
            is_panelist=True,
        )
        self.panelist_2 = User.objects.create_user(
            username='panelist-2',
            password='pass12345',
            role='faculty',
            first_name='Galileo',
            last_name='Galilei',
            is_panelist=True,
        )
        self.student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )

        # Set admin signature
        self.admin.e_signature = sig_file_admin
        self.admin.save()

        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        
        self.stage, _ = DefenseStage.objects.get_or_create(label='Project Proposal')
        
        self.team = StudentTeam.objects.create(
            name='Team TestSync',
            project_title='Test Title',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.adviser_faculty,
        )

        # Capstone Defense Schedule
        self.schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date='2026-06-30',
            start_time='09:00',
            slot_duration=60,
            room='Room 101',
            documenter=self.doc_faculty,
            created_by=self.admin,
        )

        # Assign panelists via SchedulePanelist (through model)
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=self.panelist_1, order=1, is_chair=True)
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=self.panelist_2, order=2, is_chair=False)

    def test_get_minutes_auto_creates_draft_with_comments(self):
        # Initial state: no minutes record
        self.assertFalse(DefenseMinutes.objects.filter(schedule=self.schedule).exists())

        self.client.force_authenticate(user=self.doc_faculty)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(DefenseMinutes.objects.filter(schedule=self.schedule).exists())

        # Check metadata
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        self.assertEqual(minutes.status, DefenseMinutes.STATUS_DRAFT)
        self.assertEqual(minutes.team_name, self.team.name)
        self.assertEqual(minutes.project_title, self.team.project_title)
        self.assertEqual(minutes.adviser_name, self.adviser_faculty.get_full_name())
        self.assertEqual(minutes.defense_stage_label, self.stage.label)
        self.assertEqual(minutes.room, self.schedule.room)
        self.assertEqual(minutes.documenter_name, self.doc_faculty.get_full_name())

        # Check panelist comments auto-created
        comments = minutes.panelist_comments.all().order_by('display_order')
        self.assertEqual(len(comments), 2)
        self.assertEqual(comments[0].panelist, self.panelist_1)
        self.assertEqual(comments[0].panelist_name_snapshot, self.panelist_1.get_full_name())
        self.assertEqual(comments[0].panelist_role_snapshot, 'Chair')
        self.assertEqual(comments[1].panelist, self.panelist_2)
        self.assertEqual(comments[1].panelist_name_snapshot, self.panelist_2.get_full_name())
        self.assertEqual(comments[1].panelist_role_snapshot, 'Panel Member 1')

    def test_get_minutes_permissions(self):
        # Admin can view
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Adviser can view
        self.client.force_authenticate(user=self.adviser_faculty)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Panelist 1 can view
        self.client.force_authenticate(user=self.panelist_1)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Student cannot view (403 Forbidden)
        self.client.force_authenticate(user=self.student)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_patch_minutes_comments_save_draft(self):
        # Auto-create draft
        self.client.force_authenticate(user=self.doc_faculty)
        get_response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        comments = get_response.data['panelist_comments']

        # Update comments payload
        payload = [
            {"id": comments[0]['id'], "comments": "Excellent presentation."},
            {"id": comments[1]['id'], "comments": "Need to clarify the design choices."}
        ]

        patch_response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/') # just to keep authentication clear
        patch_response = self.client.patch(f'/api/defense/minutes/{self.schedule.id}/', data=payload, format='json')
        
        self.assertEqual(patch_response.status_code, status.HTTP_200_OK)
        
        # Verify changes in DB
        c1 = MinutesPanelistComment.objects.get(id=comments[0]['id'])
        c2 = MinutesPanelistComment.objects.get(id=comments[1]['id'])
        self.assertEqual(c1.comments, "Excellent presentation.")
        self.assertEqual(c2.comments, "Need to clarify the design choices.")

    def test_patch_minutes_forbidden_for_non_documenters(self):
        # Auto-create draft
        self.client.force_authenticate(user=self.doc_faculty)
        self.client.get(f'/api/defense/minutes/{self.schedule.id}/')

        # Try to patch as adviser
        self.client.force_authenticate(user=self.adviser_faculty)
        response = self.client.patch(f'/api/defense/minutes/{self.schedule.id}/', data=[], format='json')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_submit_minutes_validation_and_success(self):
        # Create draft and comment objects
        self.client.force_authenticate(user=self.doc_faculty)
        get_response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        comments = get_response.data['panelist_comments']

        # Try submit with empty comments
        submit_response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/submit/')
        self.assertEqual(submit_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("All panelist comments must be filled before submitting.", submit_response.data['error'])

        # Fill comments
        payload = [
            {"id": comments[0]['id'], "comments": "Feedback 1"},
            {"id": comments[1]['id'], "comments": "Feedback 2"}
        ]
        self.client.patch(f'/api/defense/minutes/{self.schedule.id}/', data=payload, format='json')

        # Try submit with no documenter signature
        original_sig = self.doc_faculty.e_signature
        self.doc_faculty.e_signature = None
        self.doc_faculty.save()
        
        submit_response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/submit/')
        self.assertEqual(submit_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Please upload your e-signature first.", submit_response.data['error'])

        # Restore signature and submit
        self.doc_faculty.e_signature = original_sig
        self.doc_faculty.save()

        submit_response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/submit/')
        self.assertEqual(submit_response.status_code, status.HTTP_200_OK)
        self.assertEqual(submit_response.data['status'], DefenseMinutes.STATUS_SUBMITTED)
        self.assertIsNotNone(submit_response.data['documenter_signed_at'])

        # Check notification sent to adviser
        notification = Notification.objects.filter(recipient=self.adviser_faculty).first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.title, "Minutes Ready for Review")
        self.assertEqual(notification.message, f"The minutes for {self.team.name}'s Project Proposal defense are ready for your review and signature")

    def test_adviser_signing_flow(self):
        # Set up a submitted minutes object
        minutes = DefenseMinutes.objects.create(
            schedule=self.schedule,
            team_name=self.team.name,
            project_title=self.team.project_title,
            adviser_name=self.adviser_faculty.get_full_name(),
            defense_stage_label=self.stage.label,
            defense_date='2026-06-30',
            defense_time='09:00:00',
            room='Room 101',
            documenter_name=self.doc_faculty.get_full_name(),
            status=DefenseMinutes.STATUS_SUBMITTED,
            documenter_signed_at=timezone.now(),
            documenter_signed_by=self.doc_faculty,
        )

        # Try to sign as non-adviser
        self.client.force_authenticate(user=self.doc_faculty)
        response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/sign-adviser/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

        # Sign as adviser
        self.client.force_authenticate(user=self.adviser_faculty)
        response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/sign-adviser/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], DefenseMinutes.STATUS_ADVISER_SIGNED)
        self.assertIsNotNone(response.data['adviser_signed_at'])

        # Check notification sent to Chairman (self.admin)
        notification = Notification.objects.filter(recipient=self.admin).first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.title, "Minutes Awaiting Final Signature")
        self.assertEqual(notification.message, f"The minutes for {self.team.name}'s Project Proposal defense have been reviewed by the adviser and await your signature")

    def test_chairman_signing_and_pdf_generation(self):
        # Set up an adviser-signed minutes object
        minutes = DefenseMinutes.objects.create(
            schedule=self.schedule,
            team_name=self.team.name,
            project_title=self.team.project_title,
            adviser_name=self.adviser_faculty.get_full_name(),
            defense_stage_label=self.stage.label,
            defense_date='2026-06-30',
            defense_time='09:00:00',
            room='Room 101',
            documenter_name=self.doc_faculty.get_full_name(),
            status=DefenseMinutes.STATUS_ADVISER_SIGNED,
            documenter_signed_at=timezone.now(),
            documenter_signed_by=self.doc_faculty,
            adviser_signed_at=timezone.now(),
            adviser_signed_by=self.adviser_faculty,
        )

        # Create the panelist comment snapshots (required by PDF generator)
        MinutesPanelistComment.objects.create(
            minutes=minutes,
            panelist=self.panelist_1,
            panelist_name_snapshot=self.panelist_1.get_full_name(),
            panelist_role_snapshot='Chair',
            comments='Looks good.',
            display_order=0
        )

        # Sign as Chairman (Admin)
        self.client.force_authenticate(user=self.admin)
        response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/sign-chairman/')
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], DefenseMinutes.STATUS_COMPLETED)
        
        # Verify PDF generated and saved
        minutes.refresh_from_db()
        self.assertTrue(bool(minutes.pdf_file))
        self.assertTrue(minutes.pdf_file.name.endswith('.pdf'))

        # Check notification sent to Documenter
        notification = Notification.objects.filter(recipient=self.doc_faculty).first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.title, "Minutes Finalized")
        self.assertEqual(notification.message, f"The minutes for {self.team.name}'s Project Proposal defense have been finalized with all signatures")

        # Download the PDF
        response_pdf = self.client.get(f'/api/defense/minutes/{self.schedule.id}/pdf/')
        self.assertEqual(response_pdf.status_code, status.HTTP_200_OK)
        self.assertEqual(response_pdf['content-type'], 'application/pdf')
        self.assertTrue(len(response_pdf.content) > 0)


class MinutesEdgeCasesApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        small_gif = (
            b'\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x00\x00\x00\x21\xf9\x04'
            b'\x01\x0a\x00\x01\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02'
            b'\x02\x4c\x01\x00\x3b'
        )
        self.doc_faculty_1 = User.objects.create_user(
            username='doc-faculty-1',
            password='pass12345',
            role='faculty',
            first_name='Marie',
            last_name='Curie',
            is_documenter=True,
            e_signature=SimpleUploadedFile('sig_1.gif', small_gif, content_type='image/gif'),
        )
        self.doc_faculty_2 = User.objects.create_user(
            username='doc-faculty-2',
            password='pass12345',
            role='faculty',
            first_name='Nikola',
            last_name='Tesla',
            is_documenter=True,
            e_signature=SimpleUploadedFile('sig_2.gif', small_gif, content_type='image/gif'),
        )
        self.adviser = User.objects.create_user(
            username='adviser-user',
            password='pass12345',
            role='faculty',
            is_documenter=False,
        )
        self.student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        self.stage, _ = DefenseStage.objects.get_or_create(label='Project Proposal')
        self.team = StudentTeam.objects.create(
            name='Team TestSync',
            project_title='Test Title',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.adviser,
        )
        self.schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date='2026-06-30',
            start_time='09:00',
            slot_duration=60,
            room='Room 101',
            documenter=self.doc_faculty_1,
            created_by=self.admin,
        )

    def test_documenter_reassignment_resets_minutes(self):
        # 1. Create minutes and transition to submitted status
        self.client.force_authenticate(user=self.doc_faculty_1)
        # GET creates minutes and comment objects
        self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        comment1 = minutes.panelist_comments.first()
        if comment1:
            comment1.comments = "Some feedback"
            comment1.save()
            
        submit_response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/submit/')
        self.assertEqual(submit_response.status_code, status.HTTP_200_OK)
        
        minutes.refresh_from_db()
        self.assertEqual(minutes.status, DefenseMinutes.STATUS_SUBMITTED)
        self.assertEqual(minutes.documenter_name, self.doc_faculty_1.get_full_name())
        self.assertIsNotNone(minutes.documenter_signed_at)
        self.assertEqual(minutes.documenter_signed_by, self.doc_faculty_1)

        # 2. Admin reassigns schedule's documenter
        self.client.force_authenticate(user=self.admin)
        patch_response = self.client.patch(
            f'/api/defense/schedules/{self.schedule.id}/',
            data={'documenter_id': self.doc_faculty_2.id},
            format='json'
        )
        self.assertEqual(patch_response.status_code, status.HTTP_200_OK)
        
        # 3. Verify minutes reset to draft and clear signatures
        minutes.refresh_from_db()
        self.assertEqual(minutes.status, DefenseMinutes.STATUS_DRAFT)
        self.assertEqual(minutes.documenter_name, self.doc_faculty_2.get_full_name())
        self.assertIsNone(minutes.documenter_signed_at)
        self.assertIsNone(minutes.documenter_signed_by)

    def test_cancelled_schedule_blocks_minutes_ops(self):
        # 1. Cancel the schedule
        self.schedule.status = DefenseSchedule.STATUS_CANCELLED
        self.schedule.save()

        # 2. Attempt to GET minutes - should return 404 because no draft exists and schedule is cancelled
        self.client.force_authenticate(user=self.doc_faculty_1)
        get_response = self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        self.assertEqual(get_response.status_code, status.HTTP_404_NOT_FOUND)

        # 3. Create minutes manually to test other block checks
        self.schedule.status = DefenseSchedule.STATUS_SCHEDULED
        self.schedule.save()
        self.client.get(f'/api/defense/minutes/{self.schedule.id}/')
        
        # Now cancel the schedule again
        self.schedule.status = DefenseSchedule.STATUS_CANCELLED
        self.schedule.save()

        # 4. Try PATCHing comments - should fail
        patch_response = self.client.patch(
            f'/api/defense/minutes/{self.schedule.id}/',
            data=[{'id': 1, 'comments': 'Failed update'}],
            format='json'
        )
        self.assertEqual(patch_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Cannot modify comments for a cancelled defense schedule.", patch_response.data['detail'])

        # 5. Try submitting - should fail
        submit_response = self.client.post(f'/api/defense/minutes/{self.schedule.id}/submit/')
        self.assertEqual(submit_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Cannot submit minutes for a cancelled defense schedule.", submit_response.data['detail'])

