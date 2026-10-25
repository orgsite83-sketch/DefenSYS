from django.test import SimpleTestCase
from rest_framework.test import APITestCase

from repository.deliverables.models import DeliverableSubmission
from .models import ArchiveEntry
from .public_taxonomy import enrich_public_tags, public_facets
from .ml_search import filter_and_rank_entries
from .tests import ProjectArchiveApiTests


SPORTS = ('Objectives\nManage sports tournaments and basketball coaching schedules.\n'
          'Technical Architecture\nThe mobile application will be developed using Kotlin.')
HEALTH = ('Objectives\nMaintain hospital patient records and coordinate bed availability.\n'
          'Implementation\nThe web application is written in Python and TypeScript.')


def doc(key='one', text=SPORTS, kind='concept', year='2026-2027', project=None):
    return {'id': key, 'project_key': project or key, 'document_kind': kind,
            'file_name': 'research.pdf', 'type': 'pit', 'academic_year': year,
            'extracted_text': text}


def ids(entry, group):
    return {tag['id'] for tag in entry['library_tags'][group]}


class PublicTaxonomyTests(SimpleTestCase):
    def test_broad_subjects_have_independently_authored_positive_cases(self):
        cases = {
            'education': 'University librarians maintain academic records and library services for students.',
            'business-finance': 'Retail vendors maintain inventory and collect customer payments.',
            'agriculture-environment': 'Farmers monitor soil moisture and coordinate crop irrigation.',
            'public-services': 'Municipal clerks process citizen permits and service requests.',
            'entertainment': 'The game provides multiplayer gameplay and player progression.',
            'computing-it': 'Network analysts monitor bandwidth and investigate intrusion detection reports.',
            'transport-logistics': 'Fleet operators dispatch vehicles and track delivery routes.',
            'tourism-hospitality': 'Hotel staff maintain room availability and guest reservations.',
        }
        for subject, text in cases.items():
            with self.subTest(subject=subject):
                entry = enrich_public_tags([doc(text='Objectives\n' + text)])[0]
                self.assertIn(subject, ids(entry, 'subject'))

    def test_three_dimensions_have_canonical_ids_and_proposal_status(self):
        entry = enrich_public_tags([doc()])[0]
        self.assertEqual(ids(entry, 'subject'), {'sports-fitness'})
        self.assertEqual(ids(entry, 'technology'), {'mobile'})
        self.assertEqual(ids(entry, 'language'), {'kotlin'})
        self.assertEqual(entry['library_tags']['language'][0]['status'], 'proposed')

    def test_raw_keywords_titles_and_cover_pages_cannot_establish_filters(self):
        entry = doc(text='Python sports mobile application\nObjectives\nInvestigate stakeholder needs.')
        entry.update(topics=['python', 'approved', 'sports', 'proposed'], project_title='Sports in Python')
        enrich_public_tags([entry])
        self.assertTrue(all(not tags for tags in entry['library_tags'].values()))

    def test_uncertain_negated_reference_and_comparison_technologies_are_excluded(self):
        for text in [
            'Objectives\nInvestigate user needs.\nReferences\nA mobile application uses Kotlin.',
            'Implementation\nWe might use Python for a web application.',
            'Implementation\nWe do not use Python for a web application.',
            'Implementation\nNo mobile application will be built using Kotlin.',
            'Implementation\nFor example, a mobile application uses Kotlin.',
            'Implementation\nPrevious research developed a mobile application using Kotlin.',
            'Implementation\nThe system uses Java, not JavaScript.',
            'Implementation\nSmith et al. (2024) built a mobile application using Kotlin.',
            'Preliminary Technology Considerations\nWe use Python for the web application.',
            'Objectives\nInvestigate user needs.\nReview of Related Literature\n'
            'The mobile application is written in Kotlin.',
            'Objectives\nInvestigate user needs.\nChapter II\n'
            'A mobile application is written in Kotlin.',
        ]:
            with self.subTest(text=text):
                entry = enrich_public_tags([doc(text=text)])[0]
                self.assertFalse(ids(entry, 'technology'))
                self.assertFalse(ids(entry, 'language'))

    def test_line_wraps_do_not_turn_tentative_mentions_into_tags(self):
        entry = enrich_public_tags([doc(text='Implementation\nWe might\nuse Python to build a mobile application.')])[0]
        self.assertFalse(ids(entry, 'language'))
        self.assertFalse(ids(entry, 'technology'))

    def test_language_aliases_and_boundaries_do_not_create_unrelated_languages(self):
        entry = enrich_public_tags([doc(kind='final', text='Implementation\n'
            'The web application is written in JavaScript, C sharp and C++ with SQL queries.')])[0]
        self.assertEqual(ids(entry, 'language'), {'javascript', 'csharp', 'cpp', 'sql'})
        self.assertTrue(all(tag['status'] == 'documented' for tag in entry['library_tags']['language']))

    def test_frameworks_do_not_infer_an_undocumented_language_or_platform(self):
        entry = enrich_public_tags([doc(text='Implementation\nThe system is developed using Flutter and Django.')])[0]
        self.assertFalse(ids(entry, 'language'))
        self.assertFalse(ids(entry, 'technology'))

    def test_short_language_names_remain_valid_inside_explicit_stack_statements(self):
        for key, text in [('go', 'Implementation\nThe service is written in Go.'),
                          ('r', 'Technology Stack\nR'),
                          ('r', 'Implementation\nThe statistical tool uses R.')]:
            with self.subTest(language=key, text=text):
                entry = enrich_public_tags([doc(text=text)])[0]
                self.assertEqual(ids(entry, 'language'), {key})

    def test_ambiguous_words_and_c_family_languages_require_explicit_language_evidence(self):
        entry = enrich_public_tags([doc(text='Objectives\n'
            'Develop a detector for rust on metal using a camera.\n'
            'Implementation\nThe system is written in C and C++.')])[0]
        self.assertEqual(ids(entry, 'language'), {'c', 'cpp'})
        for text in [
            'Develop a detector for rust on metal using a camera.',
            'The gateway uses SWIFT payment network interfaces.',
            'The device uses a dart board to record exercise scores.',
        ]:
            with self.subTest(text=text):
                entry = enrich_public_tags([doc(text='Implementation\n' + text)])[0]
                self.assertFalse(ids(entry, 'language'))

    def test_school_boilerplate_is_not_an_education_subject(self):
        entry = enrich_public_tags([doc(text='University Student Concept Paper\n'
            'Objectives\nMaintain hospital patient records and coordinate bed availability.\n'
            'Scope and Limitations\nStudents in this school test the software.')])[0]
        self.assertEqual(ids(entry, 'subject'), {'health-wellbeing'})

    def test_latest_public_stage_supersedes_the_earlier_planned_stack(self):
        entries = [doc('proposal', project='same'), doc('final', HEALTH, 'final', project='same'),
                   doc('poster', '', 'poster', project='same')]
        enrich_public_tags(entries)
        for entry in entries:
            self.assertEqual(ids(entry, 'subject'), {'health-wellbeing'})
            self.assertEqual(ids(entry, 'language'), {'python', 'typescript'})
            self.assertNotIn('kotlin', ids(entry, 'language'))

    def test_missing_current_manuscript_does_not_reuse_old_planned_languages(self):
        entries = [doc('proposal', project='same'), doc('final', '', 'final', project='same')]
        enrich_public_tags(entries)
        self.assertFalse(ids(entries[0], 'language'))

    def test_administrative_attachments_are_not_classification_sources(self):
        entry = doc(text=SPORTS)
        entry['deliverable_label'] = 'Signed minutes'
        enrich_public_tags([entry])
        self.assertFalse(ids(entry, 'language'))

    def test_results_are_independent_and_text_changes_invalidate_cached_tags(self):
        first = enrich_public_tags([doc()])[0]
        first['library_tags']['language'].clear()
        other = enrich_public_tags([doc()])[0]
        self.assertEqual(ids(other, 'language'), {'kotlin'})
        updated = enrich_public_tags([doc(text=HEALTH)])[0]
        self.assertEqual(ids(updated, 'language'), {'python', 'typescript'})

    def test_projects_count_once_and_filters_are_or_within_and_between_groups(self):
        entries = enrich_public_tags([doc('one', project='same'), doc('copy', project='same'),
                                     doc('two', HEALTH), doc('unknown', '')])
        facets = public_facets(entries, {})
        sports = next(t for t in facets['subject'] if t['id'] == 'sports-fitness')
        self.assertEqual(sports['count'], 1)
        results, _ = filter_and_rank_entries(entries,
            {'subject': 'sports-fitness,health-wellbeing', 'language': 'kotlin'})
        self.assertEqual({e['project_key'] for e in results}, {'same'})
        results, _ = filter_and_rank_entries(entries, {'language': 'unspecified'})
        self.assertEqual([e['id'] for e in results], ['unknown'])

    def test_facets_respect_other_filters_year_and_selected_zero_options(self):
        entries = enrich_public_tags([doc(), doc('health', HEALTH, year='2025-2026')])
        facets = public_facets(entries, {'academic_year': '2025-2026', 'subject': 'sports-fitness'})
        self.assertEqual({t['id']: t['count'] for t in facets['subject']},
                         {'health-wellbeing': 1, 'sports-fitness': 0})
        self.assertEqual(facets['language'], [])
        self.assertNotIn('agriculture-environment', {t['id'] for t in facets['subject']})

    def test_unknown_filter_ids_fail_closed_and_subject_labels_remain_searchable(self):
        entries = enrich_public_tags([doc()])
        results, _ = filter_and_rank_entries(entries, {'language': 'unsupported-id'})
        self.assertEqual(results, [])
        results, _ = filter_and_rank_entries(entries, {'search': 'Sports & Fitness'})
        self.assertEqual(len(results), 1)


class PublicTaxonomyApiTests(APITestCase):
    setUp = ProjectArchiveApiTests.setUp

    def test_tags_and_counts_only_use_public_sources_and_get_does_not_persist_them(self):
        DeliverableSubmission.objects.filter(deliverable_id='D4.1').update(extracted_text=HEALTH)
        DeliverableSubmission.objects.filter(deliverable_id='D15').update(extracted_text=SPORTS)
        ArchiveEntry.objects.filter(status=ArchiveEntry.STATUS_APPROVED).update(extracted_text='')
        ArchiveEntry.objects.create(file_name='pending.pdf', status=ArchiveEntry.STATUS_PENDING,
                                    extracted_text=SPORTS)
        self.client.force_authenticate(self.student)
        before = list(DeliverableSubmission.objects.values('id', 'topics', 'category', 'extracted_text'))
        response = self.client.get('/api/repository/archive/')
        self.assertEqual(response.status_code, 200)
        subjects = {tag['id'] for tag in response.data['library_facets']['subject']}
        self.assertEqual(subjects, {'health-wellbeing', 'unspecified'})
        self.assertNotIn('kotlin', {tag['id'] for tag in response.data['library_facets']['language']})
        filtered = self.client.get('/api/repository/archive/', {'subject': 'health-wellbeing', 'language': 'python'})
        self.assertEqual(len(filtered.data['entries']), 1)
        self.assertEqual(filtered.data['entries'][0]['type'], 'capstone')
        empty = self.client.get('/api/repository/archive/', {'subject': 'sports-fitness'})
        self.assertEqual(empty.data['entries'], [])
        self.assertEqual(list(DeliverableSubmission.objects.values('id', 'topics', 'category', 'extracted_text')), before)
