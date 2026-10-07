from django.test import SimpleTestCase
from .project_classification import ProjectFocusClassifier, section_chunks


class ProjectClassificationTests(SimpleTestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.model = ProjectFocusClassifier()
        cls.model.train_from_examples()

    def test_agriculture_focus_survives_generic_software_boilerplate(self):
        result = self.model.predict('''CONCEPT PAPER
Smart Agriculture Crop & Soil Monitoring
1. Introduction / Background
The project combines soil and environmental sensor data with crop monitoring records.
4. Objectives
Collect soil moisture measurements and provide irrigation alerts through sensor devices.
6. Scope and Boundaries
The project includes authentication, authorization, structured storage and testing.
10. Preliminary Technology Considerations
A web-based architecture may be used with a database and logging.
''')
        self.assertEqual(result['predicted_category'], 'IoT')
        self.assertEqual(result['domain'], 'Agriculture & Environment')
        self.assertEqual(result['status'], 'estimated')
        self.assertTrue(result['evidence'])
        self.assertFalse(any(t['name'] == 'Django' for t in result['technologies']))

    def test_literature_and_tentative_stacks_do_not_establish_focus(self):
        result = self.model.predict('''Abstract
This project explores local service needs through interviews and planning workshops.
Related Work
Machine learning and neural networks trained in TensorFlow were used in prior studies.
References
IoT sensors, MQTT, Arduino and soil moisture monitoring.
''')
        self.assertEqual(result['status'], 'unresolved')
        self.assertEqual(result['technologies'], [])
        self.assertNotEqual(result['predicted_category'], 'Machine Learning')

    def test_generic_workflow_words_no_longer_train_other(self):
        result = self.model.predict('''Objectives
The hospital billing information system manages invoices, patient charges and payment records.
Proposed System Features
The billing workflows generate hospital invoices and financial reports.
''')
        self.assertEqual(result['predicted_category'], 'Information Systems')
        self.assertEqual(result['domain'], 'Healthcare')

    def test_raw_scores_and_technology_evidence_are_versioned(self):
        result = self.model.predict('''Abstract
We develop a mobile application with Flutter for Android and iOS.
Methodology
The Flutter smartphone app implements offline lessons and push notifications for students.
''')
        self.assertEqual(result['predicted_category'], 'Mobile Development')
        self.assertIn('Flutter', [t['name'] for t in result['technologies']])
        self.assertIn('input_hash', result)
        self.assertTrue(result['model_version'].startswith('project-focus-3.0-'))
        self.assertEqual(result['training_source'], 'Authored development examples; not faculty-reviewed')

    def test_missing_text_is_explicitly_unresolved(self):
        result = self.model.predict('')
        self.assertEqual(result['reason_code'], 'unreadable')
        self.assertEqual(result['predicted_category'], 'Other')

    def test_generic_text_is_not_forced_into_a_category(self):
        result = self.model.predict('Project system software development implementation design testing documentation requirements ' * 8)
        self.assertEqual(result['reason_code'], 'insufficient_evidence')
        self.assertEqual(result['predicted_category'], 'Other')

    def test_single_cue_does_not_create_a_category(self):
        result = self.model.predict('The project has an Arduino component. Its actual purpose and implementation are not described in the supplied document.')
        self.assertEqual(result['status'], 'unresolved')

    def test_section_chunks_preserve_source_passages(self):
        chunks = section_chunks('4. Objectives\nCollect soil moisture readings.\nReferences\nUse MQTT devices.')
        self.assertEqual(chunks, [{'section': 'Objectives', 'text': 'Collect soil moisture readings.', 'weight': 3}])
