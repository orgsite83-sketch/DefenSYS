from rest_framework.test import APITestCase

from defense.scheduler.models import PitEventGradingConfig
from . import test_section_editor as fixtures
from .concept_policy import context_key


class ConceptPolicyPermissionsTests(APITestCase):
    setUp = fixtures.SectionEditorTests.setUp

    def test_instructor_can_read_but_only_scoped_lead_can_change_concept_policy(self):
        event = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year',
            event_name='Concept Policy Hearing', concept_config={'enabled': True, 'required_count': 3})
        data = {'expected_section': 'BSIT-2b', 'section': 'BSIT-2b',
            'concept_policy_changes': [{'context_key': context_key(event),
                'section_policy': {'mode': 'proposals', 'required_count': 2}}]}
        self.client.force_authenticate(self.instructor)
        read = self.client.get(self.url)
        self.assertEqual(read.status_code, 200)
        self.assertFalse(read.data['can_manage_concepts'])
        self.assertEqual(self.client.patch(self.url, data, format='json').status_code, 403)
        self.client.force_authenticate(self.lead)
        changed = self.client.patch(self.url, data, format='json')
        self.assertEqual(changed.status_code, 200, changed.data)
        self.assertTrue(changed.data['can_manage_concepts'])
