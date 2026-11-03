from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from . import services, tests as fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ManagerIntegrationTaskTests(APITestCase):
    setUp = fixtures.SharedCapstoneConceptTests.setUp
    project = fixtures.SharedCapstoneConceptTests.project

    def task(self):
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/teams/my-setup/')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data['section_tasks'][0]

    def test_title_action_clears_during_faculty_review_and_returns_for_corrections(self):
        project = self.project()
        hearing = services.latest(project)
        hearing.title_workflow_version = 2
        hearing.save(update_fields=['title_workflow_version'])
        self.assertTrue(self.task()['needs_title'])
        for system in hearing.systems.all():
            system.title = f'Proposed system {system.key}'
            system.title_review = {'state': 'submitted', 'version': 1}
            system.save(update_fields=['title', 'title_review'])
        task = self.task()
        self.assertFalse(task['needs_title'])
        self.assertEqual(task['requires_action'], task['needs_files'])
        system = hearing.systems.first()
        system.title_review = {'state': 'changes_requested', 'version': 1}
        system.save(update_fields=['title_review'])
        task = self.task()
        self.assertTrue(task['needs_title'])
        self.assertTrue(task['requires_action'])

    def test_file_action_clears_after_upload_and_returns_when_rejected(self):
        project = self.project()
        services.save_system_titles(project, self.adviser,
            [{'key': key, 'title': f'System {key}'} for key in services.KEYS])
        task = self.task()
        self.assertFalse(task['needs_title'])
        self.assertTrue(task['needs_files'])
        papers = [services.upload(project, self.student, key,
            SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 Integration task test')) for key in services.KEYS]
        task = self.task()
        self.assertFalse(task['needs_files'])
        self.assertFalse(task['requires_action'])
        services.review(project, self.adviser, papers[0].pk, 'rejected', 'Clarify the system scope.')
        task = self.task()
        self.assertTrue(task['needs_files'])
        self.assertTrue(task['requires_action'])
