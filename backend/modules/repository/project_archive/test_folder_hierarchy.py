from unittest import TestCase

from .folders import archive_folder_payload, entries_in_folder


class ArchiveFolderHierarchyTests(TestCase):
    def setUp(self):
        self.base = {
            'id': 'pit', 'type': 'pit', 'academic_year': '2026-2027',
            'semester': '1st Semester', 'year_level': '2nd Year',
            'stage': 'Showcase', 'pit_event_config_id': 10,
            'team_id': 1, 'team_name': 'Team Atlas', 'has_file': True,
            'deliverable_id': 'D1', 'deliverable_label': 'Pitch deck',
        }
        self.entries = [self.base] + [
            {**self.base, 'id': 'past', 'academic_year': '2025-2026'},
            {**self.base, 'id': 'second', 'semester': '2nd Semester'},
            {**self.base, 'id': 'third', 'year_level': '3rd Year'},
            {**self.base, 'id': 'event', 'stage': 'Expo', 'pit_event_config_id': 11},
            {**self.base, 'id': 'capstone', 'type': 'capstone',
             'year_level': '4th Year', 'stage': 'Final Defense',
             'pit_event_config_id': None},
        ]

    def _open(self, group_by, titles):
        payload = archive_folder_payload(self.entries, group_by)
        for title in titles:
            folder = next(folder for folder in payload['folders']
                          if folder['title'] == title)
            payload = archive_folder_payload(self.entries, group_by, folder['key'])
        return payload

    def test_period_semester_year_event_and_team_are_separate_levels(self):
        for grouping in ('team', 'stage', 'deliverable'):
            with self.subTest(grouping=grouping):
                root = archive_folder_payload(self.entries, grouping)
                self.assertEqual([f['title'] for f in root['folders']],
                                 ['2025-2026', '2026-2027'])
                semester = self._open(grouping, ['2026-2027'])
                self.assertEqual([f['title'] for f in semester['folders']],
                                 ['1st Semester', '2nd Semester'])
                years = self._open(grouping, ['2026-2027', '1st Semester'])
                self.assertEqual([f['title'] for f in years['folders']],
                                 ['2nd Year', '3rd Year', '4th Year'])
                events = self._open(grouping, ['2026-2027', '1st Semester', '2nd Year'])
                self.assertEqual([f['title'] for f in events['folders']], ['Expo', 'Showcase'])
                if grouping == 'stage':
                    titles = ['2026-2027', '1st Semester', '2nd Year', 'Showcase']
                else:
                    last = 'Pitch deck' if grouping == 'deliverable' else 'Team Atlas'
                    titles = ['2026-2027', '1st Semester', '2nd Year', 'Showcase', last]
                leaf = self._open(grouping, titles)
                self.assertTrue(leaf['is_leaf'])
                self.assertEqual([e['id'] for e in leaf['entries']], ['pit'])
                self.assertEqual([c['title'] for c in leaf['breadcrumbs']], titles)
                self.assertEqual(leaf['file_count'], 1)
                self.assertEqual(entries_in_folder(self.entries, grouping, leaf['folder_key']),
                                 [self.base])
                parent = leaf['breadcrumbs'][-2]['key']
                self.assertFalse(archive_folder_payload(self.entries, grouping, parent)['is_leaf'])

    def test_capstone_uses_stage_above_team(self):
        leaf = self._open('team', [
            '2026-2027', '1st Semester', '4th Year', 'Final Defense', 'Team Atlas',
        ])
        self.assertEqual([e['id'] for e in leaf['entries']], ['capstone'])

    def test_same_named_events_and_tracks_keep_distinct_folders(self):
        entries = [self.base,
                   {**self.base, 'pit_event_config_id': 11},
                   {**self.base, 'type': 'capstone', 'pit_event_config_id': None}]
        payload = archive_folder_payload(entries)
        for _ in range(3):
            payload = archive_folder_payload(entries, folder_key=payload['folders'][0]['key'])
        self.assertEqual(len(payload['folders']), 3)
        self.assertEqual(len({f['key'] for f in payload['folders']}), 3)

    def test_pit_entries_with_and_without_event_config_id_share_same_event_folder(self):
        entries = [
            self.base,
            {**self.base, 'id': 'pit-no-config', 'deliverable_id': 'D2', 'pit_event_config_id': None},
        ]
        payload = archive_folder_payload(entries)
        for _ in range(3):
            payload = archive_folder_payload(entries, folder_key=payload['folders'][0]['key'])
        self.assertEqual(len(payload['folders']), 1)
        showcase_folder = payload['folders'][0]
        self.assertEqual(showcase_folder['title'], 'Showcase')
        self.assertEqual(showcase_folder['file_count'], 2)

    def test_invalid_folder_key_resets_to_root(self):
        self.assertEqual(archive_folder_payload(self.entries, folder_key='invalid!')['folder_key'], '')

    def test_shared_module_history_has_stable_seven_level_navigation(self):
        shared = {**self.base, 'section_project_id': 10, 'section_round_id': 7,
            'shared_owner': 'team', 'section': 'BSIT-2A', 'shared_system_title': 'Selected system',
            'is_proposal_history': True}
        self.entries = [shared]
        leaf = self._open('team', ['2026-2027', '1st Semester', '2nd Year', 'Showcase',
            'Shared system · BSIT-2A', 'Team Atlas', 'Proposal history'])
        self.assertTrue(leaf['is_leaf'])
        self.assertEqual(leaf['entries'], [shared])
        self.assertEqual(len(leaf['breadcrumbs']), 7)
        self.assertTrue(leaf['shared_context']['is_history'])
        self.assertEqual(entries_in_folder(self.entries, folder_key=leaf['folder_key']), [shared])

