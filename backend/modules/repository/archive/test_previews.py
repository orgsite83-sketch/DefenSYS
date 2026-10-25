"""Preview content and publication boundaries, using only the isolated test DB."""
import io
import subprocess
import tempfile
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.test import override_settings
from PIL import Image
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from student_teams.models import StudentTeam
from .models import ArchiveEntry


def png():
    stream = io.BytesIO()
    Image.new('RGB', (1200, 1600), '#7a110a').save(stream, format='PNG')
    return stream.getvalue()


class RepositoryPreviewTests(APITestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='defensys-preview-test-')
        self.addCleanup(self.folder.cleanup)
        settings = override_settings(MEDIA_ROOT=self.folder.name)
        settings.enable()
        self.addCleanup(settings.disable)
        cache.clear()
        self.reader = get_user_model().objects.create_user(username='preview-reader', role='student')
        self.client.force_authenticate(self.reader)

    def archive(self, filename='poster.png', data=None, **kwargs):
        return ArchiveEntry.objects.create(
            entry_type='pit', file_name=filename,
            file=SimpleUploadedFile(filename, png() if data is None else data), **kwargs,
        )

    def preview(self, target):
        return self.client.get('/api/repository/archive/preview/', {'target_id': target})

    def assert_image(self, response):
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'image/jpeg')
        image = Image.open(io.BytesIO(response.content))
        self.assertLessEqual(image.width, 480)
        self.assertLessEqual(image.height, 640)
        self.assertIn('private', response['Cache-Control'])
        self.assertIn('Authorization', response['Vary'])

    def test_image_is_bounded_and_approval_is_rechecked_after_caching(self):
        entry = self.archive()
        self.assert_image(self.preview(f'pit-{entry.pk}'))
        entry.status = ArchiveEntry.STATUS_NEEDS_REVISION
        entry.save(update_fields=['status'])
        self.assertEqual(self.preview(f'pit-{entry.pk}').status_code, 404)

    def test_pdf_first_page_is_rendered_without_changing_source(self):
        from reportlab.pdfgen import canvas
        stream = io.BytesIO()
        page = canvas.Canvas(stream)
        page.drawString(50, 750, 'Published project poster')
        page.showPage()
        page.save()
        entry = self.archive('poster.pdf', stream.getvalue())
        self.assert_image(self.preview(f'pit-{entry.pk}'))
        with entry.file.open('rb') as original:
            self.assertEqual(original.read(), stream.getvalue())

    def test_video_uses_a_real_frame(self):
        import imageio_ffmpeg
        path = Path(self.folder.name) / 'sample.mp4'
        subprocess.run([
            imageio_ffmpeg.get_ffmpeg_exe(), '-nostdin', '-v', 'error', '-y',
            '-f', 'lavfi', '-i', 'color=c=red:s=640x360:d=1',
            '-pix_fmt', 'yuv420p', str(path),
        ], check=True, capture_output=True, timeout=15,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        entry = self.archive('demo.mp4', path.read_bytes())
        response = self.preview(f'pit-{entry.pk}')
        self.assert_image(response)
        pixel = Image.open(io.BytesIO(response.content)).getpixel((100, 100))
        self.assertGreater(pixel[0], pixel[1] + 100)

    def test_invalid_missing_unsupported_and_anonymous_targets(self):
        self.assertEqual(self.preview('../private/file').status_code, 404)
        self.assertEqual(self.preview('pit-999999').status_code, 404)
        entry = self.archive('source.zip', b'not-an-image')
        self.assertEqual(self.preview(f'pit-{entry.pk}').status_code, 204)
        broken = self.archive('broken.pdf', b'not-a-pdf')
        self.assertEqual(self.preview(f'pit-{broken.pk}').status_code, 204)
        self.client.force_authenticate(None)
        self.assertIn(self.preview(f'pit-{entry.pk}').status_code, (401, 403))

    def test_current_file_and_owning_definition_control_visibility(self):
        year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(school_year=year, label=Semester.FIRST)
        team = StudentTeam.objects.create(name='Preview team', semester=semester,
            year_level='4th Year', level=StudentTeam.LEVEL_4_CAPSTONE, leader=self.reader)
        stage = DefenseStage.objects.create(label='Preview final')
        definition = StageDeliverable.objects.create(defense_stage=stage,
            deliverable_id='D3', label='Project poster', deliverable_type='post')
        submission = DeliverableSubmission.objects.create(team=team, stage_label=stage.label,
            deliverable_id='D3', label='Project poster', deliverable_type='post', status='accepted')
        stored = default_storage.save('previews/current.png', ContentFile(png()))
        current = DeliverableSubmissionFile.objects.create(submission=submission,
            file=stored, file_name='current.png', status='accepted')
        target = f'capstone-{submission.pk}-{current.pk}'
        self.assert_image(self.preview(target))
        definition.is_restricted = True
        definition.save(update_fields=['is_restricted'])
        self.assertEqual(self.preview(target).status_code, 404)
        definition.is_restricted = False
        definition.save(update_fields=['is_restricted'])
        current.is_current = False
        current.save(update_fields=['is_current'])
        self.assertEqual(self.preview(target).status_code, 404)
        self.assertEqual(self.preview(f'pit-deliverable-{submission.pk}-{current.pk}').status_code, 404)
