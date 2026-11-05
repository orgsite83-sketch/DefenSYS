from unittest.mock import patch
from rest_framework.test import APITestCase


class LibraryCatalogTests(APITestCase):
    def test_warm_catalog_reuses_metadata_but_changed_text_and_visibility_invalidate_it(self):
        from repository.deliverables.models import DeliverableSubmission
        from .catalog import capstone_entry_payload
        first = self.client.get('/api/repository/archive/catalog/')
        self.assertEqual(first.status_code, 200, first.data)
        with patch('repository.archive.catalog.capstone_entry_payload', side_effect=AssertionError('re-read manuscript')):
            warm = self.client.get('/api/repository/archive/catalog/')
        self.assertEqual(warm.status_code, 200, warm.data)
        submission = DeliverableSubmission.objects.get(team=self.team, deliverable_id='D4.1')
        DeliverableSubmission.objects.filter(pk=submission.pk).update(extracted_text='Updated research abstract')
        with patch('repository.archive.catalog.capstone_entry_payload', wraps=capstone_entry_payload) as payload:
            changed = self.client.get('/api/repository/archive/catalog/')
        self.assertEqual(changed.status_code, 200, changed.data)
        self.assertTrue(payload.called)
        DeliverableSubmission.objects.filter(pk=submission.pk).update(status='rejected')
        hidden = self.client.get('/api/repository/archive/catalog/')
        self.assertNotIn('capstone-' + str(submission.pk), [item['id'] for item in hidden.data['entries']])

    def test_pages_have_no_duplicates_and_do_not_include_restricted_materials(self):
        import json
        from .services import all_visible_entries
        expected = {entry['project_key'] for entry in all_visible_entries(self.student)}
        seen = []
        for offset in range(len(expected)):
            response = self.client.get('/api/repository/archive/catalog/', {'limit': 1, 'offset': offset, 'sort': 'title'})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['pagination']['total'], len(expected))
            self.assertEqual(response.data['pagination']['has_more'], offset + 1 < len(expected))
            for entry in response.data['entries']:
                seen.append(entry['project_key'])
                self.assertNotIn('D15', [json.loads(item['key'])[-1] for item in entry['available_deliverables'] if item['key'] != 'unassigned'])
        self.assertEqual(set(seen), expected)
        self.assertEqual(len(seen), len(expected))

    def setUp(self):
        from .tests import ProjectArchiveApiTests
        ProjectArchiveApiTests.setUp(self)
        self.client.force_authenticate(self.student)

    def test_catalog_is_bounded_and_does_not_build_the_legacy_full_payload(self):
        with patch('repository.archive.services.all_visible_entries', side_effect=AssertionError('full catalog built')):
            response = self.client.get('/api/repository/archive/catalog/', {'limit': 1})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertLessEqual(len(response.data['entries']), 1)
        for entry in response.data['entries']:
            self.assertTrue(entry['catalog_summary'])
            self.assertNotIn('extracted_text', entry)
            self.assertNotIn('project_entries', entry)

    def test_project_detail_and_deliverable_filter_use_actual_labels(self):
        from .services import all_visible_entries
        entries = all_visible_entries(self.student)
        keys = {entry['project_key'] for entry in entries}
        response = self.client.get('/api/repository/archive/catalog/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual({entry['project_key'] for entry in response.data['entries']}, keys)
        for summary in response.data['entries']:
            detail = self.client.get('/api/repository/archive/project/', {'project_key': summary['project_key']})
            self.assertEqual(detail.status_code, 200, detail.data)
            self.assertEqual({entry['id'] for entry in detail.data['entries']},
                             {entry['id'] for entry in entries if entry['project_key'] == summary['project_key']})
            for definition in detail.data['deliverables']:
                selected = self.client.get('/api/repository/archive/catalog/', {'deliverable': definition['key']})
                self.assertEqual(selected.status_code, 200, selected.data)
                self.assertIn(summary['project_key'], [entry['project_key'] for entry in selected.data['entries']])
                self.assertTrue(definition['label'])

    def test_unknown_project_pagination_and_authentication_fail_closed(self):
        self.assertEqual(self.client.get('/api/repository/archive/project/', {'project_key': 'capstone:secret'}).status_code, 404)
        self.assertEqual(self.client.get('/api/repository/archive/catalog/', {'limit': 'invalid'}).status_code, 400)
        self.assertEqual(self.client.get('/api/repository/archive/catalog/', {'offset': '90000'}).status_code, 400)
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get('/api/repository/archive/catalog/').status_code, 401)
