from django.test import SimpleTestCase

from repository.archive.ml_search import build_suggestions, filter_and_rank_entries, matches_search, score_entry


class ArchiveMlSearchTests(SimpleTestCase):
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

    def test_multiword_query_matches_across_title_and_topics(self):
        entry = {'project_title': 'Hospital Ward System', 'topics': ['management']}
        self.assertTrue(matches_search(entry, 'hospital management'))
        self.assertFalse(matches_search(entry, 'hospital robotics'))

    def test_concept_filter_scopes_results_and_suggestions(self):
        entries = [
            {'id': 'concept-1', 'project_title': 'Hospital Concept', 'document_kind': 'concept'},
            {'id': 'video-1', 'project_title': 'Hospital Promo', 'document_kind': 'video'},
        ]
        results, suggestions = filter_and_rank_entries(entries, {'search': 'hospital', 'document_kind': 'concept'})
        self.assertEqual([entry['id'] for entry in results], ['concept-1'])
        self.assertEqual({item['entry_id'] for item in suggestions}, {'concept-1'})
