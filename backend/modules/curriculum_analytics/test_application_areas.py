from django.test import SimpleTestCase

from .application_areas import application_area, UNRESOLVED_AREA


class ApplicationAreaTests(SimpleTestCase):
    def doc(self, text, pk='current'):
        return {'id': pk, 'display_name': 'Project proposal', '_raw_text': text, 'uploaded_at': '2026-10-01'}

    def test_school_boilerplate_does_not_hide_wellness_purpose(self):
        result = application_area([self.doc('Objectives\n'
            'Students use a wellness directory and record private self-reported feelings.\n'
            'Scope and Limitations\nA school classroom prototype for campus evaluation.')])
        self.assertEqual(result['application_area'], 'Health & Wellbeing')
        self.assertEqual({e['document_id'] for e in result['application_area_evidence']}, {'current'})
        self.assertTrue(all(e['term'].lower() in e['excerpt'].lower() for e in result['application_area_evidence']))

    def test_service_area_is_independent_of_computing_platform(self):
        text = 'Objectives\nHelp volunteer tutors offer sessions in available subjects.\n'
        for platform in ('', 'Implementation\nThe web application uses Django.',
                         'Implementation\nThe mobile application uses Flutter.'):
            with self.subTest(platform=platform):
                self.assertEqual(application_area([self.doc(text + platform)])['application_area'],
                                 'Learning & Academic Support')

    def test_cover_citations_tentative_and_broad_words_do_not_establish_area(self):
        cases = [
            'Library book catalog\nObjectives\nInvestigate stakeholder needs.',
            'Objectives\nSupport campus students and school staff.',
            'Objectives\nInterview stakeholders.\nReferences\nA library book catalog.',
            'Objectives\nWe might create a library book catalog.',
            'Objectives\nNo library book catalog is planned; it is out of scope.',
            'Objectives\nProvide a library service.',
        ]
        for text in cases:
            with self.subTest(text=text):
                self.assertEqual(application_area([self.doc(text)])['application_area'], UNRESOLVED_AREA)

    def test_line_wrapped_specific_terms_keep_source_evidence(self):
        result = application_area([self.doc('Proposed System Features\n'
            'Publish a document\nlibrary of approved forms with version dates.')])
        self.assertEqual(result['application_area'], 'Information & Document Services')
        self.assertTrue(result['application_area_evidence'])

    def test_primary_document_wins_over_duplicate_old_sources(self):
        current = self.doc('Objectives\nProvide wellness resources and a private reflection check-in.')
        old = self.doc('Objectives\nPublish cafeteria menus and vendor prices.', pk='old')
        result = application_area([old, old, current], primary_id='current')
        self.assertEqual(result['application_area'], 'Health & Wellbeing')

    def test_competing_areas_in_primary_remain_unresolved(self):
        current = self.doc('Objectives\nPublish cafeteria menus and vendor prices.\n'
                           'Provide wellness resources and a private reflection check-in.')
        old = self.doc('Objectives\nPublish cafeteria menus and vendor prices.', pk='old')
        self.assertEqual(application_area([current, old], primary_id='current')['application_area'], UNRESOLVED_AREA)
