from django.test import SimpleTestCase

from .project_profile import build_project_profile


class ProjectProfileTests(SimpleTestCase):
    def document(self, text, label='Approved Concept Paper', pk='current'):
        return {'id': pk, 'label': label, 'display_name': f'D4 · {label}',
                'uploaded_at': '2026-10-05', '_raw_text': text}

    def test_copies_background_with_wraps_and_stops_at_objectives(self):
        text = ('1. Background and Rationale\nCampus Event Hub centralizes campus event records.\n'
                'Objectives\n1. To create an event directory.\n2. To evaluate usability.\n'
                'Proposed System Features\n(cid:127) Event creation and\npublishing\n'
                '(cid:127) Student registration\n(cid:127) Digital attendance tracking\n'
                'Scope and Boundaries\nOnly campus activities are included.\n'
                'References\nMobile application and Android development.')
        profile = build_project_profile([self.document(text)], {'document_id': 'current'})
        self.assertNotIn('features', profile)
        self.assertEqual(profile['description']['document_id'], 'current')
        self.assertEqual(profile['description']['section'], 'Background and Rationale')
        self.assertEqual(profile['description']['text'], 'Campus Event Hub centralizes campus event records.')
        self.assertEqual(profile['platforms'], [])

    def test_objectives_and_features_are_not_reinterpreted_as_project_context(self):
        text = ('Specific Objectives\n1. To enable online registration.\n'
                '2. To generate attendance reports.\n3. To assess usability.\n'
                'References\n1. Mobile application feature planning.')
        profile = build_project_profile([self.document(text), self.document(text, pk='copy')],
                                        {'document_id': 'current'})
        self.assertIsNone(profile['description'])
        self.assertNotIn('features', profile)

    def test_platform_preserves_proposal_status_and_excludes_tentative_text(self):
        proposed = self.document('Abstract\nThe proposed web application manages event registration.\n'
                                 'Preliminary Technology Considerations\nAndroid may be used.')
        profile = build_project_profile([proposed], {'document_id': 'current'})
        self.assertEqual([(p['name'], p['status']) for p in profile['platforms']], [('Web', 'proposed')])
        tentative = self.document('Methodology\nA web-based architecture may be\nused after approval.')
        self.assertEqual(build_project_profile([tentative], {})['platforms'], [])

    def test_missing_text_does_not_invent_facts_from_deliverable_label(self):
        profile = build_project_profile([self.document('', label='Final mobile manuscript')], {})
        self.assertIsNone(profile['description'])
        self.assertNotIn('features', profile)
        self.assertEqual(profile['platforms'], [])

    def test_primary_source_context_takes_precedence_over_an_older_concept(self):
        current = self.document('Abstract\nThe current project organizes appointment schedules and patient records.',
                                label='Project proposal')
        old = self.document('Background of the Study\nThe older concept focused on managing campus events and registration.', pk='older')
        profile = build_project_profile([old, current], {'document_id': 'current'})
        self.assertEqual(profile['description']['section'], 'Abstract')
        self.assertEqual(profile['description']['document_id'], 'current')
        self.assertNotIn('campus events', profile['description']['text'])

    def test_prefers_background_with_its_actual_heading_over_abstract(self):
        text = ('Abstract\nThis abstract describes the project proposal and planned development work.\n'
                'CHAPTER 1 INTRODUCTION\n1.1 Background of the Study\n'
                'Students currently manage event registration through separate\nforms and records.\n'
                '1.2 Significance of the Study\nDo not include this next section.')
        profile = build_project_profile([self.document(text)], {})
        self.assertEqual(profile['description']['section'], 'Background of the Study')
        self.assertEqual(profile['description']['text'],
                         'Students currently manage event registration through separate forms and records.')
        self.assertFalse(profile['description']['truncated'])

    def test_long_excerpt_is_bounded_and_explicitly_marked_as_shortened(self):
        text = 'Background of the Study\n' + 'Students use separate forms to register for campus events. ' * 35
        profile = build_project_profile([self.document(text)], {})
        self.assertLessEqual(len(profile['description']['text']), 1001)
        self.assertTrue(profile['description']['truncated'])
