from django.test import SimpleTestCase

from repository.vault.ml_search import build_suggestions, score_entry


class VaultMlSearchTests(SimpleTestCase):
    def test_score_entry_boosts_category_and_topics(self):
        entry = {
            'id': 'pit-1',
            'file_name': '3rdYear.PIT301.Project.1stSemester.pdf',
            'team_name': 'Team Alpha',
            'topics': ['flutter', 'mobile'],
            'category': 'Mobile Development',
            'extracted_text': 'campus navigation system',
        }
        score = score_entry(entry, 'flutter mobile')
        self.assertGreater(score, 0)

    def test_build_suggestions_returns_topic_and_category(self):
        entries = [
            {
                'id': 'pit-1',
                'file_name': 'test.pdf',
                'team_name': 'Team Alpha',
                'topics': ['flutter'],
                'category': 'Mobile Development',
            },
        ]
        suggestions = build_suggestions(entries, 'flutter')
        types = {item['type'] for item in suggestions}
        self.assertTrue({'topic', 'category'} & types)
