from django.test import SimpleTestCase
from unittest.mock import patch
from unittest.mock import patch
from .project_classification import ProjectFocusClassifier, section_chunks
from .classification_taxonomy import MODEL_VERSION


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

    def test_document_memo_reuses_unchanged_text_and_invalidates_for_text_or_model(self):
        model = ProjectFocusClassifier()
        model.train_from_examples()
        text = 'Implementation\nThe web application uses Django and PostgreSQL for library loan records.'
        with patch.object(model, 'predict', wraps=model.predict) as predict:
            first = model.classify_document(text)
            first['technologies'].clear()
            second = model.classify_document(text)
            self.assertTrue(second['technologies'])  # Callers cannot mutate the memo.
            self.assertEqual(predict.call_count, 1)
            model.classify_document(text + '\nThe application uses React.')
            self.assertEqual(predict.call_count, 2)
            model.model_version += '-updated'
            model.classify_document(text)
            self.assertEqual(predict.call_count, 3)

    def test_document_memo_reuses_unchanged_text_and_invalidates_for_text_or_model(self):
        model = ProjectFocusClassifier()
        model.train_from_examples()
        text = 'Implementation\nThe web application uses Django and PostgreSQL for library loan records.'
        with patch.object(model, 'predict', wraps=model.predict) as predict:
            first = model.classify_document(text)
            first['technologies'].clear()
            second = model.classify_document(text)
            self.assertTrue(second['technologies'])  # Callers cannot mutate the memo.
            self.assertEqual(predict.call_count, 1)
            model.classify_document(text + '\nThe application uses React.')
            self.assertEqual(predict.call_count, 2)
            model.model_version += '-updated'
            model.classify_document(text)
            self.assertEqual(predict.call_count, 3)

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
        self.assertTrue(result['model_version'].startswith(f'{MODEL_VERSION}-'))
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

    def test_functional_descriptions_establish_project_focus_without_stack_names(self):
        cases = [
            ('Objectives\nPublish activity schedules and organize event records.\n'
             'Proposed System Features\nOnline sign-ups and attendance tracking support event-management tools.',
             'Information Systems'),
            ('Objectives\nRecord presenting complaints during patient intake.\n'
             'Proposed System Features\nNurses use the triage queue and triage history for handoff.',
             'Information Systems'),
            ('Objectives\nMaintain bed records and update patient transfers.\n'
             'Proposed System Features\nWard-management tools report bed availability and occupancy reports.',
             'Information Systems'),
            ('Objectives\nSupport route optimization and compare feasible routes using distance and travel-time criteria.\n'
             'Expected Outputs\nRoute comparison provides data-driven planning alternatives for dispatchers.',
             'Data Science'),
            ('Objectives\nMaintain alumni information with employment records and career history.\n'
             'Proposed System Features\nProfile management and a searchable directory support authorized staff.',
             'Information Systems'),
        ]
        for text, expected in cases:
            with self.subTest(expected=expected, text=text):
                result = self.model.predict(text)
                self.assertEqual(result['predicted_category'], expected)
                self.assertEqual(result['status'], 'estimated')
                self.assertGreaterEqual(len(result['evidence']), 2)
                self.assertEqual(result['technologies'], [])

    def test_line_wraps_and_hyphen_variants_preserve_cues_and_excerpts(self):
        result = self.model.predict('Objectives\nThe occupancy information system manages patient\n'
            'transfers and maintains bed\navailability.\nProposed System Features\nWard–management provides patient assignments.')
        self.assertEqual(result['predicted_category'], 'Information Systems')
        cues = {hit['term'] for hit in result['evidence']}
        self.assertIn('patient transfers', cues)
        self.assertIn('bed availability', cues)
        self.assertIn('ward management', cues)
        self.assertTrue(all(hit['section'] in ('Objectives', 'Proposed System Features') for hit in result['evidence']))

    def test_cited_and_tentative_operational_features_are_not_project_evidence(self):
        result = self.model.predict('Objectives\nWe investigate community needs through interviews.\n'
            'Preliminary Technology Considerations\nWe might use route optimization and route comparison.\n'
            'Related Work\nPrior studies provide patient intake, triage queue and ward-management systems.\n'
            'References\nAn event-management platform provides attendance tracking and event records.')
        self.assertEqual(result['status'], 'unresolved')
        self.assertEqual(result['evidence'], [])
        self.assertEqual(result['technologies'], [])

    def test_routing_does_not_confuse_computer_networks_with_fleet_optimization(self):
        result = self.model.predict('Objectives\nConfigure packet routing and switching across routers.\n'
            'Methodology\nEvaluate network topology and bandwidth in the campus network infrastructure.')
        self.assertEqual(result['predicted_category'], 'Network Systems')

    def test_triage_workflow_does_not_imply_a_trained_machine_learning_model(self):
        result = self.model.predict('Objectives\nSupport patient intake, the triage queue and triage history.\n'
            'Methodology\nConfigurable criteria support patient handoff and records management.')
        self.assertEqual(result['predicted_category'], 'Information Systems')
        self.assertNotIn('Machine Learning', result['secondary_categories'])

    def test_concept_functions_establish_information_system_without_platform_or_fake_score(self):
        # Authored scenarios, not copies of the evaluated cohort's papers.
        cases = [
            'Search historical repair tickets. Record newly submitted requests.',
            'Display available rehearsal rooms. Confirm reservations for approved groups.',
            'Collect appliance inspection reports. Review submitted reports for maintenance staff.',
            'Maintain approved service notices. Show current announcements to visitors.',
            'Upload permitted forms for applicants. Find archived documents by reference number.',
        ]
        for functions in cases:
            with self.subTest(functions=functions):
                result = self.model.predict('CONCEPT PAPER\n03 Project Objectives\n'
                    'Support the local service workflow.\n04 Proposed System and Key Functions\n' +
                    functions + '\n06 Scope and Limitations\nPlatform selection follows stakeholder review.')
                self.assertEqual(result['predicted_category'], 'Information Systems')
                self.assertEqual(result['decision_method'], 'concept_functions')
                self.assertEqual(result['status'], 'estimated')
                self.assertIsNone(result['confidence_score'])
                self.assertIsNone(result['margin'])
                self.assertGreaterEqual(len({h['function'] for h in result['evidence']}), 2)
                self.assertTrue(all(h['section'] == 'Proposed System And Key Functions' for h in result['evidence']))
                self.assertEqual(result['technologies'], [])
                self.assertTrue(result['top_3'])  # Raw model suggestions remain separate.

    def test_concept_sections_keep_methodology_and_scope_out_of_functional_evidence(self):
        chunks = section_chunks('CONCEPT PAPER\n01 Background and Rationale\nExisting practice.\n'
            '03 Project Objectives\nIdentify stakeholder needs.\n04 Proposed System and Key Functions\n'
            'Show current service notices.\n06 Scope and Limitations\nMaintain records.\n'
            '07 Proposed Development and Validation Plan\nCollect inspection reports.\n'
            '08 Risk Considerations and Safeguards\nCloud storage and distributed files reduce loss.')
        self.assertEqual(chunks[0]['section'], 'Background And Rationale')
        self.assertFalse(any(c['text'] == 'and Rationale' for c in chunks))
        self.assertEqual(self.model.predict('CONCEPT PAPER\n' + '\n'.join(
            f"{c['section']}\n{c['text']}" for c in chunks))['status'], 'unresolved')

    def test_concept_fallback_rejects_generic_tentative_cited_manual_and_repeated_operations(self):
        cases = [
            'Objectives\nInterview stakeholders and conduct testing.\n'
            'Proposed System Features\nUse authentication, storage, backups and validation.',
            'Proposed System Features\nWe might maintain repair records. We could display request history.',
            'Objectives\nStudy institutional service needs.\n'
            'References\nMaintain repair records. Display request history.',
            'Background and Rationale\nStaff maintain repair records and display request history manually.\n'
            'Objectives\nInvestigate the problem through interviews.',
            'Proposed System Features\nSearch room listings. Find room listings. Browse room listings.',
            'Proposed System Features\nEvaluate search accuracy and user completion of tasks.\n'
            'Provide searchable book records. Create a prototype for library availability.',
            'Proposed System Features\nMaintain handwritten service records. Display paper-based request history.',
            'Proposed System Features\nShow current service notices.\n'
            'Scope and Limitations\nMaintain repair records.\n'
            'Proposed Development and Validation Plan\nCollect inspection reports.',
        ]
        for body in cases:
            with self.subTest(body=body):
                self.assertEqual(self.model.predict('CONCEPT PAPER\n' + body)['status'], 'unresolved')

    def test_specialist_focus_remains_primary_when_concept_also_manages_information(self):
        result = self.model.predict('CONCEPT PAPER\nAbstract\n'
            'An IoT embedded sensor prototype collects soil moisture measurements through an ESP32.\n'
            'Proposed System Features\nRecord measurement history. Display archived reports.\n'
            'Methodology\nThe microcontroller sends telemetry through an MQTT gateway.')
        self.assertEqual(result['predicted_category'], 'IoT')
        self.assertEqual(result['decision_method'], 'naive_bayes')
        self.assertIsNotNone(result['confidence_score'])

    def test_functional_fallback_does_not_hide_conflicting_specialist_evidence(self):
        from unittest.mock import patch
        probabilities = [0.9 if c == 'Web Development' else 0.1 if c == 'IoT' else 0
                         for c in self.model.classifier.classes_]
        with patch.object(self.model.classifier, 'predict_proba', return_value=[probabilities]):
            result = self.model.predict('CONCEPT PAPER\nProposed System Features\n'
                'An embedded sensor collects soil moisture readings.\n'
                'Record measurement history. Display archived reports.')
        self.assertEqual(result['status'], 'unresolved')
        self.assertEqual(result['decision_method'], 'naive_bayes')

    def test_archiver_supports_functional_estimate_without_numeric_confidence(self):
        import tempfile
        from pathlib import Path
        from .document_archiver import DocumentArchiver
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'paper.pdf'
            source.write_bytes(b'concept paper')
            result = DocumentArchiver(str(Path(temporary) / 'archive')).archive_document(
                str(source), 'paper.pdf', 'Information Systems', None, {})
            self.assertEqual(result['status'], 'success')
            self.assertEqual(result['confidence'], 'Not scored (proposed functions)')
            self.assertEqual(Path(result['archive_path']).read_bytes(), b'concept paper')
