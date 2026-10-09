from django.test import SimpleTestCase
from rest_framework.test import APITestCase

from repository.deliverables.models import DeliverableSubmission
from .library import document_kind, document_overview, enrich_library_entry
from .models import ArchiveEntry, UserBookShelf
from .tests import ProjectArchiveApiTests


class DocumentOverviewTests(SimpleTestCase):
    def test_background_excludes_cover_toc_and_following_section(self):
        text = ('CONCEPT PAPER\nTeam Members<br/>Ana Cruz\n'
                'Background of the Study .......... 6\nObjectives .......... 7\n\f'
                '1. Background of the Study\n'
                'Hospital staff coordinate patient admissions and bed availability across wards.\n'
                '1.1. Objectives\nBuild the application.\n')
        overview = document_overview(text)
        self.assertEqual(overview['overview_label'], 'Background of the Study')
        self.assertEqual(overview['overview_page'], 2)
        self.assertNotIn('Ana Cruz', overview['overview_text'])
        self.assertNotIn('Build the application', overview['overview_text'])

    def test_actual_abstract_is_preferred_without_generating_text(self):
        overview = document_overview('Background of the Study\n' + 'Background context. ' * 5 +
                                     '\nObjectives\nA goal.\nAbstract\n' + 'Existing author abstract. ' * 5 + '\nReferences\nA citation.')
        self.assertEqual(overview['overview_label'], 'Abstract')
        self.assertTrue(overview['overview_text'].startswith('Existing author abstract.'))

    def test_poster_pdf_is_a_poster_and_video_is_not_a_manuscript(self):
        self.assertEqual(document_kind({'file_name': 'poster.pdf', 'deliverable_label': 'Research Poster'}), 'poster')
        self.assertEqual(document_kind({'file_name': 'Final_Manuscript_Promo.mp4'}), 'video')
        self.assertEqual(document_kind({'file_name': 'chapters_1-3.pdf'}), 'chapters')

    def test_unlinked_projects_are_never_grouped_by_team_name(self):
        entries = [enrich_library_entry({'id': str(number), 'file_name': 'concept.pdf', 'team_name': 'Same name'}) for number in (1, 2)]
        self.assertNotEqual(entries[0]['project_key'], entries[1]['project_key'])

    def test_chapter_labels_preserve_the_actual_range(self):
        entry = enrich_library_entry({'id': '1', 'file_name': 'chapters_1-2.pdf'})
        self.assertEqual(entry['document_label'], 'Chapters 1–2')


class PublicLibraryTests(APITestCase):
    setUp = ProjectArchiveApiTests.setUp

    def test_concept_scope_and_project_title(self):
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/repository/archive/', {'document_kind': 'concept'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['entries']), 1)
        self.assertEqual(response.data['entries'][0]['display_title'], 'Secure Vault Search')
        self.assertEqual(response.data['entries'][0]['document_label'], 'Concept Paper')

    def test_only_approved_pit_uploads_are_public(self):
        ArchiveEntry.objects.create(file_name='pending_paper.pdf', status=ArchiveEntry.STATUS_PENDING)
        self.client.force_authenticate(self.student)
        entries = self.client.get('/api/repository/archive/').data['entries']
        self.assertNotIn('pending_paper.pdf', [entry['file_name'] for entry in entries])

    def test_linked_pit_archive_uses_the_team_project_title(self):
        upload = ArchiveEntry.objects.get(status=ArchiveEntry.STATUS_APPROVED)
        upload.team = self.team
        upload.save(update_fields=['team'])
        self.client.force_authenticate(self.student)
        entries = self.client.get('/api/repository/archive/', {'type': 'pit'}).data['entries']
        self.assertEqual(entries[0]['display_title'], 'Secure Vault Search')

    def test_history_and_saving_are_independent_and_private(self):
        self.client.force_authenticate(self.student)
        target = self.client.get('/api/repository/archive/', {'document_kind': 'concept'}).data['entries'][0]['id']
        url = '/api/repository/archive/shelf/'
        self.assertEqual(self.client.post(url, {'target_id': target, 'is_saved': True}, format='json').status_code, 200)
        self.assertEqual(self.client.get(url).data['recent'], [])
        self.client.post(url, {'target_id': target, 'opened': True}, format='json')
        self.client.post(url, {'target_id': target, 'status': 'reading', 'last_read_page': 2,
                               'total_pages': 10, 'progress_percent': 20}, format='json')
        shelf = self.client.get(url).data
        self.assertEqual(len(shelf['recent']), 1)
        self.assertEqual(len(shelf['saved']), 1)
        self.assertEqual(shelf['recent'][0]['reading_progress'], 20)
        self.client.force_authenticate(self.faculty)
        self.assertEqual(self.client.get(url).data['recent'], [])
        self.client.force_authenticate(self.student)
        self.client.delete(url)
        shelf = self.client.get(url).data
        self.assertEqual(shelf['recent'], [])
        self.assertEqual(len(shelf['saved']), 1)

    def test_reopening_deduplicates_and_never_marks_complete(self):
        self.client.force_authenticate(self.student)
        target = self.client.get('/api/repository/archive/').data['entries'][0]['id']
        for _ in range(2):
            self.client.post('/api/repository/archive/shelf/', {'target_id': target, 'opened': True}, format='json')
        item = UserBookShelf.objects.get(user=self.student, target_id=target)
        self.assertEqual(item.status, 'reading')
        self.assertEqual(item.progress_percent, 0)
        self.assertEqual(len(self.client.get('/api/repository/archive/shelf/').data['recent']), 1)

    def test_removed_or_restricted_outputs_are_not_exposed_by_history(self):
        self.client.force_authenticate(self.student)
        target = self.client.get('/api/repository/archive/', {'document_kind': 'concept'}).data['entries'][0]['id']
        self.client.post('/api/repository/archive/shelf/', {'target_id': target, 'opened': True}, format='json')
        submission = DeliverableSubmission.objects.get(team=self.team, deliverable_id='D4.1')
        submission.status = DeliverableSubmission.STATUS_REJECTED
        submission.save(update_fields=['status'])
        self.assertEqual(self.client.get('/api/repository/archive/shelf/').data['recent'], [])
        self.assertEqual(self.client.post('/api/repository/archive/shelf/', {'target_id': target, 'opened': True}, format='json').status_code, 404)

    def test_saved_project_contains_only_its_public_outputs(self):
        self.client.force_authenticate(self.student)
        entry = self.client.get('/api/repository/archive/', {'document_kind': 'concept'}).data['entries'][0]
        target = f"project:{entry['project_key']}"
        url = '/api/repository/archive/shelf/'
        response = self.client.post(url, {'target_id': target, 'is_saved': True}, format='json')
        self.assertEqual(response.status_code, 200)
        saved = self.client.get(url).data['saved']
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0]['document_kind'], 'project')
        self.assertEqual(saved[0]['display_title'], 'Secure Vault Search')
        self.assertEqual([item['id'] for item in saved[0]['project_entries']], [entry['id']])
        self.assertEqual(self.client.get(url).data['recent'], [])
