from django.test import SimpleTestCase

from .application_areas import application_area, UNRESOLVED_AREA, AREA_VERSION


class ApplicationAreaTests(SimpleTestCase):
    def test_chapter_manuscripts_are_eligible_without_bypassing_admin_restrictions(self):
        from types import SimpleNamespace
        from .explorer import _is_project_document
        for label in ('Chapter 1-3', 'Final Chapter 1-3', 'Chapter 1-5 and Appendices', 'Chapters I-III'):
            with self.subTest(label=label):
                config = SimpleNamespace(label=label, is_restricted=False, is_defense_material=False)
                self.assertTrue(_is_project_document(label, config))
                config.is_restricted = True
                self.assertFalse(_is_project_document(label, config))
        self.assertFalse(_is_project_document('Chapter 1-3 approval form'))
        self.assertFalse(_is_project_document('Attendance sheet for Chapter 1-3'))

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

    def test_capstone_service_areas_have_two_cue_families(self):
        cases = {
            'Agriculture & Farming': 'Farmers monitor crop irrigation and soil moisture readings.',
            'Environment & Waste Management': 'Automate waste sorting and recyclable material identification.',
            'Healthcare Services': 'Manage patient intake, triage and hospital bed availability.',
            'Transport & Logistics': 'Compare delivery routes and dispatch fleet vehicles.',
            'Commerce & Inventory': 'Manage retail inventory stock and customer orders.',
            'Finance & Payments': 'Record accounting ledger transactions and payroll payments.',
            'Public Safety & Emergency Response': 'Coordinate emergency response and rescue dispatch alerts.',
            'Government & Public Services': 'Manage barangay permits and resident records for citizens.',
            'Academic Administration': 'Coordinate capstone defense scheduling and evaluation.',
            'Careers & Employment': 'Maintain alumni employment records and career history.',
            'Tourism & Hospitality': 'Manage hotel bookings and accommodation reservations.',
            'Security & Access Management': 'Perform vulnerability detection and penetration testing.',
        }
        for label, sentence in cases.items():
            with self.subTest(label=label):
                result = application_area([self.doc('Objectives\n' + sentence)])
                self.assertEqual(result['application_area'], label)
                self.assertEqual(result['application_area_reason_code'], 'supported')
                self.assertEqual(result['application_area_version'], AREA_VERSION)
                self.assertEqual(len(result['application_area_evidence']), 2)

    def test_manuscript_chapter_and_objective_aliases_keep_page_provenance(self):
        text = ('Technical manuscript\nCHAPTER I\nINTRODUCTION\n'
                'The study investigates waste sorting challenges.\f'
                '1.3 Objectives of the Study\n'
                'Automate waste sorting and recyclable material identification.\f'
                'CHAPTER II REVIEW OF RELATED LITERATURE\n'
                'Objectives\nPublish cafeteria menus and vendor prices.\f'
                'CHAPTER III\nRESEARCH METHODOLOGY\n'
                'Interview participants to assess project feasibility.')
        result = application_area([self.doc(text)])
        self.assertEqual(result['application_area'], 'Environment & Waste Management')
        self.assertEqual({e['page'] for e in result['application_area_evidence']}, {2})
        self.assertEqual({e['section'] for e in result['application_area_evidence']}, {'Objectives'})

    def test_explicit_purpose_outranks_other_services_in_background(self):
        result = application_area([self.doc('Background of the Study\n'
            'The hospital schedules patient appointments.\nSpecific Objectives\n'
            'Manage delivery routes and dispatch fleet vehicles.')])
        self.assertEqual(result['application_area'], 'Transport & Logistics')

    def test_context_can_supply_purpose_without_objective_heading(self):
        result = application_area([self.doc('CHAPTER 1 INTRODUCTION\n'
            'This project automates waste sorting and recyclable material identification.')])
        self.assertEqual(result['application_area'], 'Environment & Waste Management')

    def test_reference_and_scope_subheadings_do_not_leak_into_purpose(self):
        for heading in ('Review of Related Literature', 'Significance of the Study', 'Scope and Limitations'):
            with self.subTest(heading=heading):
                result = application_area([self.doc('Objectives of the Study\n'
                    'Investigate stakeholder requirements through consultation.\n' + heading + '\n'
                    'A hospital manages patient appointments and triage.')])
                self.assertEqual(result['application_area'], UNRESOLVED_AREA)

    def test_cues_cannot_be_combined_across_unrelated_sections(self):
        result = application_area([self.doc('Background\n'
            'The library needs service improvements for community members.\nObjectives\n'
            'Collect book preferences and evaluate general stakeholder requirements.')])
        self.assertEqual(result['application_area'], UNRESOLVED_AREA)

    def test_distinct_failure_reasons_and_no_probability_for_rules(self):
        for documents, reason in (
            ([], 'no_documents'),
            ([self.doc('')], 'unreadable'),
            ([self.doc('References\nA library publishes a book catalog and lending records.')], 'missing_purpose_sections'),
            ([self.doc('Objectives\nInvestigate stakeholder requirements through consultation.')], 'unsupported_area'),
        ):
            with self.subTest(reason=reason):
                result = application_area(documents)
                self.assertEqual(result['application_area_status'], 'unresolved')
                self.assertEqual(result['application_area_reason_code'], reason)
                self.assertTrue(result['application_area_reason'])
                self.assertNotIn('confidence', result)
        self.assertEqual(application_area([], source_reason='unrelated_documents')[
            'application_area_reason_code'], 'unrelated_documents')

    def test_ambiguous_source_names_candidates_without_counting_repeated_copies(self):
        current = self.doc('Objectives\nPublish cafeteria menus and vendor prices.\n'
                           'Provide wellness resources and a private reflection check-in.')
        result = application_area([current, current], primary_id='current')
        self.assertEqual(result['application_area_reason_code'], 'ambiguous')
        self.assertEqual(set(result['application_area_candidates']), {'Food & Dining Services', 'Health & Wellbeing'})

    def test_generic_authentication_does_not_establish_security_purpose(self):
        result = application_area([self.doc('Objectives\n'
            'Provide authentication, access control and verification of submitted records.')])
        self.assertEqual(result['application_area'], UNRESOLVED_AREA)

    def test_general_objective_takes_priority_over_secondary_modules(self):
        text = ('CHAPTER I\n1.3.1GeneralObjectives\n'
                'Manage patient triage and clinical admission.\n1.3.2SpecificObjectives\n'
                'Publish events and registration activities. Maintain retail inventory stock and orders.')
        result = application_area([self.doc(text)])
        self.assertEqual(result['application_area'], 'Healthcare Services')
        self.assertEqual({e['section'] for e in result['application_area_evidence']}, {'General Objectives'})

    def test_service_delivery_and_generic_organization_are_not_transport_or_events(self):
        result = application_area([self.doc('General Objective\n'
            'Improve healthcare service delivery through patient admission and clinical triage. '
            'The organization registers staff training milestones.')])
        self.assertEqual(result['application_area'], 'Healthcare Services')

    def test_specialised_service_refines_generic_workflow_with_actual_evidence(self):
        result = application_area([self.doc('General Objectives\n'
            'Manage hospital pharmacy medicine dispensing and inventory stock levels.')])
        self.assertEqual(result['application_area'], 'Pharmacy & Medication Services')
        self.assertEqual({e['term'] for e in result['application_area_evidence']}, {'pharmacy', 'dispensing'})

    def test_new_service_categories_use_document_functions(self):
        cases = {
            'Workforce & Personnel Services': 'Manage employee attendance and daily time records.',
            'Academic Administration': 'Provide faculty self-assessment and rank upgrade evaluation.',
            'Elections & Voting': 'Manage election candidates, voters and secure ballots.',
            'Legal & Case Management': 'Manage legal case documents and hearing schedules.',
            'Social Welfare & Assistance': 'Manage social work eligibility documents and patient assistance.',
            'Construction & Project Operations': 'Monitor construction projects, progress and materials.',
        }
        for area, functions in cases.items():
            with self.subTest(area=area):
                self.assertEqual(application_area([self.doc('General Objectives\n' + functions)])['application_area'], area)

    def test_real_competing_objectives_retain_contested_passages(self):
        result = application_area([self.doc('General Objectives\n'
            'Provide wellness resources and private reflection check-in. Publish cafeteria menus and vendor prices.')])
        self.assertEqual(result['application_area_reason_code'], 'ambiguous')
        self.assertEqual(len(result['application_area_candidate_evidence']), 2)
        self.assertTrue(all(c['priority'] == 4 for c in result['application_area_candidate_evidence']))
        self.assertTrue(all(e['document_id'] == 'current' and e['page'] == 1
                            for c in result['application_area_candidate_evidence'] for e in c['evidence']))

    def test_specific_goal_list_under_one_heading_cannot_override_main_purpose(self):
        result = application_area([self.doc('Objectives\n'
            'Develop a legal case management service for hearing schedules. '
            'Specifically, maintain accounting ledger transactions and payroll payments.')])
        self.assertEqual(result['application_area'], 'Legal & Case Management')
