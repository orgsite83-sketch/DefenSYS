"""Evaluation accounting tests use artificial predictions, never accuracy claims."""
import json
import tempfile
import warnings
from pathlib import Path
from unittest.mock import patch

from django.test import SimpleTestCase
from sklearn.exceptions import InconsistentVersionWarning

from .classification_evaluation import STUDY_LABELS, evaluate_projects, reviewed_dataset, source_documents
from .project_classification import ProjectFocusClassifier


class EvaluationTests(SimpleTestCase):
    def record(self, number, **changes):
        return dict(project_id=str(number), project_family_id=str(number), reviewed=True,
                    text=f'Independent manuscript number {number}', label=STUDY_LABELS[0],
                    split='test', **changes)

    def load(self, records):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'reviewed.json'
            path.write_text(json.dumps(records), encoding='utf-8')
            return reviewed_dataset(path)

    def test_rejects_unreviewed_labels_and_family_or_text_leakage(self):
        unreviewed = self.record(1)
        unreviewed['reviewed'] = False
        with self.assertRaisesRegex(ValueError, 'reviewed=true'):
            self.load([unreviewed])
        first, second = self.record(1), self.record(2)
        first['split'] = 'train'
        second['project_family_id'] = first['project_family_id']
        with self.assertRaisesRegex(ValueError, 'project family'):
            self.load([first, second])
        same_project = dict(first, project_family_id='different', split='test')
        with self.assertRaisesRegex(ValueError, 'project family'):
            self.load([first, same_project])
        second['project_family_id'] = '2'
        second['text'] = first['text'].upper()
        with self.assertRaisesRegex(ValueError, 'Duplicate manuscript'):
            self.load([first, second])

    def test_40_project_accuracy_is_measured_without_rounding_up(self):
        class ArtificialModel:
            model_version = 'test-only'
            training_source = 'Artificial predictions for accounting tests'

            def predict(self, text, **kwargs):
                number = int(text.rsplit(' ', 1)[1])
                label = STUDY_LABELS[0] if number < 37 else STUDY_LABELS[1]
                return dict(status='estimated', predicted_category=label, reason_code='supported',
                            decision_method='naive_bayes', top_3=[{'category': label, 'probability': 93.0}])
        records = self.load([self.record(i) for i in range(40)])
        records.append(dict(records[0]))  # A second copy cannot add a project.
        report = evaluate_projects(ArtificialModel(), records)
        result = report['primary_naive_bayes']
        self.assertEqual(result['eligible_projects'], 40)
        self.assertEqual(result['correct_projects'], 37)
        self.assertEqual(result['accuracy_percent'], 92.5)
        self.assertTrue(result['meets_target'])
        self.assertEqual(sum(map(sum, result['confusion_matrix'])), 40)
        self.assertEqual(len(report['predictions']), 40)

    def test_abstentions_extraction_and_processing_failures_stay_in_denominator(self):
        class ArtificialModel:
            model_version = 'test-only'
            training_source = 'Artificial predictions for accounting tests'

            def predict(self, text, *, allow_function_fallback=True):
                if text == 'processing failure':
                    raise RuntimeError('Artificial failure')
                accepted = bool(text) and allow_function_fallback
                return dict(status='estimated' if accepted else 'unresolved',
                            predicted_category=STUDY_LABELS[0] if accepted else 'Other',
                            reason_code='supported' if accepted else 'insufficient_evidence',
                            decision_method='concept_functions' if accepted else 'naive_bayes',
                            top_3=[{'category': STUDY_LABELS[0], 'probability': 55.0}])
        records = [self.record(i) for i in range(3)]
        records[1]['text'] = ''
        records[2]['text'] = 'processing failure'
        report = evaluate_projects(ArtificialModel(), self.load(records))
        self.assertEqual(report['primary_naive_bayes']['accuracy'], 0)
        self.assertEqual(report['primary_naive_bayes']['eligible_projects'], 3)
        self.assertEqual(report['primary_naive_bayes']['unresolved_projects'], 3)
        self.assertAlmostEqual(report['deployed_hybrid']['accuracy'], 1 / 3)
        self.assertEqual(report['primary_naive_bayes']['abstention_reasons']['processing_error'], 1)

    def test_persisted_model_version_mismatch_falls_back_without_overwriting(self):
        model = ProjectFocusClassifier()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'model.pkl'
            path.write_bytes(b'test placeholder, never unpickled')
            original = path.read_bytes()

            def mismatch(source):
                warnings.warn(InconsistentVersionWarning(estimator_name='MultinomialNB',
                    current_sklearn_version='1.9.1', original_sklearn_version='1.8.0'))

            with patch('repository.deliverables.project_classification.pickle.load', side_effect=mismatch):
                model.load_model(path)
            self.assertTrue(model.is_trained)
            self.assertEqual(path.read_bytes(), original)

    def test_ml_only_mode_does_not_accept_the_functional_fallback(self):
        model = ProjectFocusClassifier()
        text = ('CONCEPT PAPER\nProject Proposal\nObjectives\n'
                'Maintain records and update requests.\nProposed System Features\n'
                'Display notices and view deadlines.')
        self.assertEqual(model.predict(text)['decision_method'], 'concept_functions')
        result = model.predict(text, allow_function_fallback=False)
        self.assertEqual(result['decision_method'], 'naive_bayes')
        self.assertEqual(result['status'], 'unresolved')

    def test_individual_sources_are_classified_separately_and_latest_supported_source_wins(self):
        class ArtificialModel:
            model_version = 'test-only'
            training_source = 'Artificial source-selection accounting'

            def predict(self, text, **kwargs):
                if '\n\n' in text:
                    raise AssertionError('PDFs must not be concatenated into a prediction')
                label = STUDY_LABELS[0] if text == 'current manuscript' else STUDY_LABELS[1]
                return dict(status='estimated', predicted_category=label, reason_code='supported',
                            decision_method='naive_bayes', confidence_score=90,
                            top_3=[{'category': label, 'probability': 90}])
        row = self.record(1)
        row['documents'] = [
            dict(id='file:1', label='Project manuscript', text='older manuscript', uploaded_at='2026-01-01'),
            dict(id='file:2', label='Project manuscript', text='current manuscript', uploaded_at='2026-02-01'),
        ]
        report = evaluate_projects(ArtificialModel(), self.load([row]))
        self.assertEqual(report['primary_naive_bayes']['correct_projects'], 1)
        self.assertEqual(report['predictions'][0]['naive_bayes_source'], 'file:2')

    def test_duplicate_individual_source_cannot_leak_across_splits(self):
        first, second = self.record(1), self.record(2)
        first['split'] = 'train'
        source = dict(id='file:1', label='Project manuscript', text='Same underlying manuscript')
        first['documents'] = [source]
        second['documents'] = [dict(source, id='file:2')]
        with self.assertRaisesRegex(ValueError, 'Duplicate manuscript'):
            self.load([first, second])

    def test_legacy_export_source_lengths_must_agree_exactly(self):
        row = self.record(1)
        row['text'] = 'first source\n\nsecond source'
        row['sources'] = [dict(id='file:1', label='Chapter 1-3', extracted_characters=12),
                          dict(id='file:2', label='Final Chapter 1-3', extracted_characters=13)]
        self.assertEqual([d['_raw_text'] for d in source_documents(row)], ['first source', 'second source'])
        row['sources'][0]['extracted_characters'] = 3
        with self.assertRaisesRegex(ValueError, 'legacy source lengths'):
            source_documents(row)
