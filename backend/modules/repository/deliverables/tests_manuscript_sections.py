from unittest.mock import patch

from django.test import SimpleTestCase

from .manuscript_sections import manuscript_sections
from .project_classification import ProjectFocusClassifier, FEATURE_VERSION, input_hash, section_chunks


class ManuscriptSectionTests(SimpleTestCase):
    def test_contents_and_chapter_two_cannot_supply_implementation_evidence(self):
        text = ('TABLE OF CONTENTS\nObjectives ........ 1\nImplementation ........ 2\n'
                'Technology Stack ........ 3\fCHAPTER I\n1.3 Statement of Objectives\n'
                'Maintain inspection records. Display current notices.\fCHAPTER II\n'
                'Review of Related Literatures\nObjectives\nUse neural networks and TensorFlow.\n'
                'Implementation\nDevelop an Android Flutter smartphone application.\fCHAPTER III\n'
                '3.4 Software Requirements\nThe proposed implementation uses Django and PostgreSQL.')
        chunks = section_chunks(text)
        self.assertEqual({c['page'] for c in chunks}, {2, 4})
        combined = ' '.join(c['text'] for c in chunks)
        self.assertNotIn('TensorFlow', combined)
        self.assertNotIn('Flutter', combined)
        self.assertIn('PostgreSQL', combined)

    def test_numbered_fused_headings_and_inline_paragraphs_are_canonical(self):
        sections = manuscript_sections('CHAPTER I\n'
            '1.3.1GeneralObjectives To improve clinical patient admission.\n'
            '1.3.2SpecificObjectives\nMaintain records and display patient requests.\n'
            '1.4SignificanceoftheStudy\nA fleet delivery company benefits indirectly.')
        self.assertEqual([p['section'] for p in sections], ['General Objectives', 'Specific Objectives'])
        self.assertEqual([p['tier'] for p in sections], [4, 2])
        self.assertNotIn('fleet', ' '.join(p['text'] for p in sections))

    def test_prose_that_starts_with_implementation_is_not_a_heading(self):
        sections = manuscript_sections('Objectives\nMaintain current repair records.\n'
            'Implementation will improve communication between inspectors.\nDisplay open requests.')
        self.assertEqual(len(sections), 1)
        self.assertEqual(sections[0]['section'], 'Objectives')

    def test_relevant_late_sections_survive_long_excluded_literature(self):
        text = ('CHAPTER I\nObjectives\nMaintain inspection records.\nCHAPTER II\n' +
                'Prior study considers neural networks.\n' * 2500 +
                '\fCHAPTER III\n3.5 Technical Architecture\nThe web application uses Django and PostgreSQL.')
        self.assertGreater(len(text), 80000)
        chunks = section_chunks(text)
        self.assertTrue(any('Django' in c['text'] for c in chunks))
        self.assertFalse(any('neural networks' in c['text'] for c in chunks))

    def test_unknown_numbered_subsection_stops_previous_objective(self):
        sections = manuscript_sections('1.3 Objectives\nMaintain inspection records.\n'
            '1.4 Research Participants\nParticipants enjoy mobile games on Android phones.')
        self.assertNotIn('Android', ' '.join(s['text'] for s in sections))

    def test_bibliography_cannot_reopen_evidence_with_a_cited_heading(self):
        chunks = section_chunks('Objectives\nMaintain inspection records.\n'
            'References\nImplementation\nA Flutter Android application uses TensorFlow.')
        self.assertNotIn('Flutter', ' '.join(c['text'] for c in chunks))

    def test_old_processing_cache_is_recomputed_without_retraining_artifact(self):
        model = ProjectFocusClassifier()
        model.train_from_examples()
        text = 'Implementation\nThe web application uses Django for hospital billing information.'
        old = {'model_version': model.model_version, 'input_hash': input_hash(text), 'status': 'unresolved'}
        with patch.object(model, 'predict', wraps=model.predict) as predict:
            result = model.classify_document(text, old)
        self.assertEqual(predict.call_count, 1)
        self.assertEqual(result['feature_version'], FEATURE_VERSION)
