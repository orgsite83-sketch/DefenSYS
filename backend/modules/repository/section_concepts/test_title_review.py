"""One displayed name must never confirm another proposal or its documents."""
from django.test import override_settings
from rest_framework.test import APITestCase

from repository.deliverables import concepts
from . import services, tests as fixtures
from . import test_shared_deliverables as shared_fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SelectedTitleReviewTests(APITestCase):
    setUp = fixtures.SharedSystemConceptTests.setUp
    rubric = fixtures.SharedSystemConceptTests.rubric
    data = fixtures.SharedSystemConceptTests.data
    slot = fixtures.SharedSystemConceptTests.slot
    configure = fixtures.SharedSystemConceptTests.configure
    titles = fixtures.SharedSystemConceptTests.titles
    action = fixtures.SharedSystemConceptTests.action

    def test_missing_module_round_inherits_the_shared_workflow_without_writing(self):
        from repository.deliverables.models import ConceptRound
        before = ConceptRound.objects.count()
        state = concepts.payload(self.team, self.event, actor=self.pm)
        self.assertEqual(state['title_workflow_version'], services.latest(self.project).title_workflow_version)
        self.assertEqual(ConceptRound.objects.count(), before)
        self.assertFalse(state['concepts'][0]['title_review']['can_accept'])

    def test_legacy_saved_module_title_can_be_accepted_without_files_or_upgrade(self):
        from repository import title_workflow
        concepts.save_titles(self.team, self.event, self.titles('Module'), actor=self.pm, draft=True)
        state = concepts.payload(self.team, self.event, actor=self.first)
        self.assertTrue(state['concepts'][0]['title_review']['can_accept'])
        self.assertFalse(self.team.deliverable_submissions.exists())
        response = self.module_action(action='accept_title', concept_key='c1')
        self.assertEqual(response.status_code, 200, response.data)
        current = concepts.latest_round(self.team, self.event)
        self.assertEqual(current.title_workflow_version, 1)
        self.assertTrue(current.concepts[0]['faculty_confirmed'])
        self.assertFalse(current.concepts[1].get('faculty_confirmed', False))
        title_workflow.team_action(self.team, self.event, self.first, 'request_title_revision', 'c1', reason='Clarify scope.')
        concepts.save_titles(self.team, self.event, self.titles('Revised module'), actor=self.pm, draft=True)
        state = concepts.payload(self.team, self.event, actor=self.first)
        self.assertTrue(state['concepts'][0]['title_review']['can_accept'])

    def test_legacy_system_title_review_preserves_existing_paper_approval(self):
        from repository import title_workflow
        from django.core.files.uploadedfile import SimpleUploadedFile
        services.save_system_titles(self.project, self.pm, self.titles('System'))
        file = services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('system.pdf', b'%PDF-1.4 shared'))
        services.review(self.project, self.first, file.pk, 'accepted')
        self.assertTrue(services.payload(self.project, self.first)['systems'][0]['title_review']['can_accept'])
        response = self.action('accept_title', concept_key='c1')
        self.assertEqual(response.status_code, 200, response.data)
        file.refresh_from_db()
        self.assertEqual(file.status, 'accepted')
        self.assertEqual(file.revision, 1)
        self.assertEqual(services.latest(self.project).title_workflow_version, 1)
        title_workflow.system_action(self.project, self.first, 'request_title_revision', 'c1', reason='Explain the title.')
        services.save_system_titles(self.project, self.pm, self.titles('System'))
        self.assertTrue(services.payload(self.project, self.first)['systems'][0]['title_review']['can_accept'])

    def test_legacy_upload_requires_its_own_saved_title(self):
        from django.core.exceptions import ValidationError
        from django.core.files.uploadedfile import SimpleUploadedFile
        from repository.deliverables.services import upsert_submission
        values = self.titles('Module')
        values[0]['title'] = ''
        concepts.save_titles(self.team, self.event, values, actor=self.pm, draft=True)
        with self.assertRaisesMessage(ValidationError, 'Save the matching'):
            upsert_submission(self.team, self.event.label, 'CONCEPTS', 'module.pdf', '10 B', self.pm,
                file=SimpleUploadedFile('module.pdf', b'%PDF-1.4 module'), slot_key='c1:paper')
        self.assertFalse(self.team.deliverable_submissions.exists())

    def module_action(self, actor=None, **values):
        actor = actor or self.first
        state = concepts.payload(self.team, self.event, actor=actor)
        self.client.force_authenticate(actor)
        payload = {
            'team_id': self.team.pk, 'stage_label': self.event.label,
            'action': 'confirm_title', 'concept_key': 'c2',
            'round_id': state['round_id'], 'review_token': state['module_review_token'], **values}
        if payload.get('review_token') is None:
            payload.pop('review_token', None)
        return self.client.post('/api/repository/deliverables/concepts/', payload, format='json')

    def test_system_confirmation_is_selected_and_does_not_accept_files(self):
        services.save_system_titles(self.project, self.pm, self.titles('Draft'))
        response = self.action('confirm_title', concept_key='c2')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([s['confirmed'] for s in response.data['systems']], [False, True, False])
        self.assertFalse(response.data['cleared'])
        self.assertEqual(response.data['review_progress']['papers_accepted'], 0)

    def test_can_confirm_one_system_while_other_names_are_blank(self):
        response = self.action('confirm_title', concept_key='c1', title='First proposed system')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([s['confirmed'] for s in response.data['systems']], [True, False, False])

    def test_system_confirmation_rejects_unassigned_student_and_unknown_key(self):
        for actor in (self.pm, self.second):
            self.assertIn(self.action('confirm_title', actor, concept_key='c1', title='Changed').status_code, (403, 404))
        self.assertEqual(self.action('confirm_title', concept_key='unknown', title='Invalid').status_code, 400)

    def test_stale_system_confirmation_cannot_confirm_next_title(self):
        state = services.payload(self.project, self.first)
        self.assertEqual(self.action('confirm_title', concept_key='c1', title='First').status_code, 200)
        self.client.force_authenticate(self.first)
        response = self.client.post(f'{fixtures.URL}{self.project.pk}/', {
            'action': 'confirm_title', 'concept_key': 'c2', 'title': 'Stale',
            'round_id': state['round_id'], 'review_token': state['review_token']}, format='json')
        self.assertEqual(response.status_code, 409)
        self.assertFalse(services.latest(self.project).systems.get(key='c2').confirmed)

    def test_module_confirmation_is_selected_and_preserves_other_titles(self):
        concepts.save_titles(self.team, self.event, self.titles('Draft module'), actor=self.pm)
        response = self.module_action(title='Reviewed module two')
        self.assertEqual(response.status_code, 200, response.data)
        current = concepts.latest_round(self.team, self.event)
        self.assertEqual([bool(c.get('faculty_confirmed')) for c in current.concepts], [False, True, False])
        self.assertEqual(current.concepts[0]['title'], 'Draft module c1')
        self.assertEqual(current.concepts[1]['title'], 'Reviewed module two')
        self.assertIsNone(current.endorsed_at)

    def test_module_confirmation_requires_fresh_round_and_token(self):
        concepts.save_titles(self.team, self.event, self.titles('Draft'), actor=self.pm)
        state = concepts.payload(self.team, self.event, actor=self.first)
        self.assertEqual(self.module_action(review_token=None).status_code, 409)
        self.assertEqual(self.module_action(round_id=state['round_id']+1).status_code, 409)
        self.assertEqual(self.module_action().status_code, 200)
        self.assertEqual(self.module_action(concept_key='c1', review_token=state['module_review_token']).status_code, 409)

    def test_student_cannot_confirm_module_name(self):
        concepts.save_titles(self.team, self.event, self.titles('Draft'), actor=self.pm)
        self.assertEqual(self.module_action(self.pm).status_code, 403)

    def test_module_title_change_invalidates_only_the_matching_file(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from repository.deliverables.services import upsert_submission, review_submission
        concepts.save_titles(self.team, self.event, self.titles('Draft'), actor=self.pm)
        rows = []
        for key in ('c1', 'c2'):
            submission = upsert_submission(self.team, self.event.label, 'CONCEPTS', f'{key}.pdf', '10 B',
                self.pm, file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 module'), slot_key=f'{key}:paper')
            row = submission.files.get(is_current=True, slot_key=f'{key}:paper')
            review_submission(self.team, self.event.label, 'CONCEPTS', 'accepted', '', self.first, file_id=row.pk)
            rows.append(row)
        self.assertEqual(self.module_action(concept_key='c1', title='Changed first module').status_code, 200)
        for row in rows:
            row.refresh_from_db()
        self.assertEqual([r.status for r in rows], ['pending', 'accepted'])
        self.assertEqual([r.revision for r in rows], [1, 1])


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ConfiguredTitleReviewTests(APITestCase):
    setUp = shared_fixtures.SharedDeliverableTests.setUp
    rubric = shared_fixtures.SharedDeliverableTests.rubric
    data = shared_fixtures.SharedDeliverableTests.data
    slot = shared_fixtures.SharedDeliverableTests.slot
    configure = shared_fixtures.SharedDeliverableTests.configure
    titles = shared_fixtures.SharedDeliverableTests.titles
    custom = shared_fixtures.SharedDeliverableTests.custom
    definition = shared_fixtures.SharedDeliverableTests.definition
    state = shared_fixtures.SharedDeliverableTests.state
    upload = shared_fixtures.SharedDeliverableTests.upload
    accept = shared_fixtures.SharedDeliverableTests.accept

    def test_progress_counts_extra_attachments_and_excludes_defense_timed_materials(self):
        from . import shared_deliverables as shared
        definitions = self.custom([
            self.definition('ATTACH', 'multiple', file_policy={'mode': 'multiple', 'min_files': 1, 'max_files': 3}),
            self.definition('DECK'),
        ])
        # New setup normalizes timing; an existing hearing may retain a defense-timed snapshot.
        definitions[1]['requirement_timing'] = 'defense'
        hearing = services.latest(self.project)
        hearing.shared_requirements_snapshot = definitions
        hearing.save(update_fields=['shared_requirements_snapshot'])
        self.upload('ATTACH', '')
        self.upload('ATTACH', '')
        profile = shared.resolve(self.team, self.event)
        self.assertEqual(shared.document_progress(profile)['documents_required'], 2)
        documents = self.state()['requirements'][0]['documents']
        self.accept('ATTACH', documents[0]['key'])
        progress = shared.document_progress(shared.resolve(self.team, self.event))
        self.assertEqual(progress['documents_accepted'], 1)
        self.assertEqual(progress['documents_required'], 2)

    def test_title_change_invalidates_only_its_configured_system_files(self):
        self.custom([self.definition('PER', 'concepts'), self.definition('ONCE')])
        services.save_system_titles(self.project, self.pm, self.titles('Draft'))
        for key in services.KEYS:
            self.upload('PER', f'{key}:paper')
            self.accept('PER', f'{key}:paper')
        self.upload('ONCE')
        self.accept('ONCE')
        services.confirm_system_title(self.project, self.first, 'c1')
        self.assertTrue(all(d['documents'][0]['file']['status'] == 'accepted' for d in self.state()['requirements']))
        services.confirm_system_title(self.project, self.first, 'c1', 'Changed first system')
        per, once = self.state()['requirements']
        self.assertEqual([d['file']['status'] for d in per['documents']], ['pending', 'accepted', 'accepted'])
        self.assertEqual(once['documents'][0]['file']['status'], 'accepted')
