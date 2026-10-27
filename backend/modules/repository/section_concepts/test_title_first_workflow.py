from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from repository import title_workflow as workflow
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRevisionRequest, ConceptRound
from repository.deliverables.services import upsert_submission, review_submission
from . import services, shared_deliverables as shared
from . import test_shared_deliverables as fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class TitleFirstWorkflowTests(APITestCase):
    def setUp(self):
        fixtures.SharedDeliverableTests.setUp(self)
        services.latest(self.project).__class__.objects.filter(project=self.project).update(title_workflow_version=2)
    rubric = fixtures.SharedDeliverableTests.rubric
    data = fixtures.SharedDeliverableTests.data
    slot = fixtures.SharedDeliverableTests.slot
    configure = fixtures.SharedDeliverableTests.configure
    titles = fixtures.SharedDeliverableTests.titles

    def system(self, key='c1', title='Shared system'):
        workflow.system_action(self.project, self.pm, 'submit_title', key, title)
        return workflow.system_action(self.project, self.first, 'accept_title', key)

    def module(self, key='c1', title='Module one'):
        return workflow.team_action(self.team, self.event, self.pm, 'submit_title', key, title)

    def accept_module(self, key='c1'):
        return workflow.team_action(self.team, self.event, self.first, 'accept_title', key)

    def paper(self, key='c1'):
        submission = upsert_submission(self.team, self.event.label, 'CONCEPTS', f'{key}.pdf', '20 B', self.pm,
            file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 supporting paper'), slot_key=f'{key}:paper')
        return submission.files.get(is_current=True, slot_key=f'{key}:paper')

    def review(self, file, status='accepted', scope='paper', reason=''):
        return review_submission(self.team, self.event.label, 'CONCEPTS', status, reason, self.first,
            file_id=file.pk, revision_scope=scope, title_review_token=concepts.module_review_token(self.team, self.event))

    def test_module_submission_and_upload_do_not_wait_for_system_acceptance(self):
        workflow.system_action(self.project, self.pm, 'submit_title', 'c1', 'Shared system')
        state = concepts.payload(self.team, self.event, actor=self.pm)
        self.assertTrue(state['concepts'][0]['title_review']['can_submit'])
        self.assertFalse(services.latest(self.project).systems.get(key='c1').confirmed)
        current = self.module()
        file = self.paper()
        self.assertEqual(file.status, 'pending')
        review = concepts.payload(self.team, self.event, actor=self.first)['concepts'][0]['title_review']
        self.assertTrue(review['can_accept'])
        self.accept_module()
        current.refresh_from_db()
        self.assertTrue(workflow.accepted(current.concepts[0], workflow.parent_for(current, 'c1')))
        self.assertFalse(services.latest(self.project).systems.get(key='c1').confirmed)

    def test_each_module_title_is_reviewed_independently_without_any_file(self):
        self.system()
        current = self.module()
        self.accept_module()
        current.refresh_from_db()
        self.assertTrue(workflow.accepted(current.concepts[0], workflow.parent_for(current, 'c1')))
        self.module('c2')
        state = concepts.payload(self.team, self.event, actor=self.first)
        self.assertTrue(state['concepts'][1]['title_review']['can_accept'])
        self.assertFalse(services.shared_clearance(services.latest(self.project)))

    def test_seeded_title_is_not_submitted_and_read_does_not_create_round(self):
        before = ConceptRound.objects.count()
        state = concepts.payload(self.team, self.event, actor=self.first)
        self.assertEqual(ConceptRound.objects.count(), before)
        self.assertFalse(state['concepts'][0]['title_review']['can_accept'])
        with self.assertRaises(ValidationError):
            workflow.team_action(self.team, self.event, self.first, 'accept_title', 'c1')
        self.assertEqual(ConceptRound.objects.count(), before)

    def test_file_may_support_submitted_title_but_requires_title_acceptance(self):
        self.system()
        self.module()
        file = self.paper()
        with self.assertRaisesMessage(ValidationError, 'before accepting its file'):
            self.review(file)
        self.accept_module()
        self.review(file)
        file.refresh_from_db()
        self.assertEqual(file.status, 'accepted')

    def test_no_title_upload_is_rejected_without_creating_a_submission(self):
        self.system()
        with self.assertRaisesMessage(ValidationError, 'Submit the matching'):
            self.paper()
        self.assertFalse(self.team.deliverable_submissions.exists())

    def test_checklist_explains_missing_titles_and_unlocks_only_submitted_slots(self):
        from repository.deliverables.services import stage_payload
        before = ConceptRound.objects.count()
        state = stage_payload(self.team, self.event.label, evaluator=self.pm)
        item = next(item for item in state['pre'] if item['id'] == 'CONCEPTS')
        self.assertEqual(ConceptRound.objects.count(), before)
        self.assertIn('in Team', item['document_slots'][0]['upload_blocker'])
        self.module()
        state = stage_payload(self.team, self.event.label, evaluator=self.pm)
        item = next(item for item in state['pre'] if item['id'] == 'CONCEPTS')
        self.assertEqual(item['document_slots'][0]['upload_blocker'], '')
        self.assertIn('in Team', item['document_slots'][1]['upload_blocker'])

    def test_title_and_paper_is_one_request_with_ordered_resubmission(self):
        self.system()
        self.module()
        self.accept_module()
        old = self.paper()
        self.review(old)
        self.review(old, 'rejected', 'title_and_paper', 'Choose a more suitable module.')
        self.assertEqual(ConceptRevisionRequest.objects.count(), 1)
        state = concepts.payload(self.team, self.event, actor=self.pm)
        request = state['concepts'][0]['title_review']['revision_request']
        self.assertEqual(request['scope'], 'title_and_paper')
        self.assertEqual(state['concepts'][0]['title_review']['state'], 'changes_requested')
        with self.assertRaises(ValidationError):
            self.paper()
        self.module(title='Better module')
        self.accept_module()
        with self.assertRaises(ValidationError):
            self.review(old)
        new = self.paper()
        self.review(new)
        self.assertEqual(ConceptRevisionRequest.objects.count(), 1)

    def test_paper_only_preserves_title_and_requires_new_upload(self):
        self.system()
        self.module()
        self.accept_module()
        file = self.paper()
        self.review(file, 'rejected', reason='Clarify the methods.')
        current = concepts.latest_round(self.team, self.event)
        self.assertEqual(current.concepts[0]['title_review']['state'], 'accepted')
        with self.assertRaisesMessage(ValidationError, 'new file revision'):
            self.review(file)
        self.review(self.paper())

    def test_title_only_request_without_file_and_unchanged_reapproval_retains_file(self):
        self.system()
        self.module()
        self.accept_module()
        workflow.team_action(self.team, self.event, self.first, 'request_title_revision', 'c1', reason='Clarify the title.')
        self.module()
        self.accept_module()
        file = self.paper()
        self.review(file)
        workflow.team_action(self.team, self.event, self.first, 'request_title_revision', 'c1', reason='Explain the scope.')
        with self.assertRaises(ValidationError):
            self.review(file)
        self.module()
        self.accept_module()
        self.review(file)

    def test_parent_revision_invalidates_only_matching_module_connection(self):
        self.system()
        self.system('c2', 'Second system')
        self.module()
        self.accept_module()
        self.module('c2', 'Second module')
        self.accept_module('c2')
        workflow.system_action(self.project, self.first, 'request_title_revision', 'c1', reason='Change system scope.')
        workflow.system_action(self.project, self.pm, 'submit_title', 'c1', 'Changed system')
        workflow.system_action(self.project, self.first, 'accept_title', 'c1')
        current = concepts.latest_round(self.team, self.event)
        self.assertFalse(workflow.accepted(current.concepts[0], workflow.parent_for(current, 'c1')))
        self.assertTrue(workflow.accepted(current.concepts[1], workflow.parent_for(current, 'c2')))
        with self.assertRaisesMessage(ValidationError, 'Resubmit this module title'):
            self.paper()
        state = concepts.payload(self.team, self.event, actor=self.pm)
        self.assertTrue(state['concepts'][0]['title_review']['can_submit'])
        self.module(title='Module for the revised system')
        self.accept_module()

    def test_stale_combined_request_is_atomic(self):
        self.system()
        self.module()
        self.accept_module()
        file = self.paper()
        with self.assertRaisesMessage(ValueError, 'title changed'):
            review_submission(self.team, self.event.label, 'CONCEPTS', 'rejected', 'Rework both.', self.first,
                file_id=file.pk, revision_scope='title_and_paper', title_review_token='stale')
        file.refresh_from_db()
        self.assertEqual(file.status, 'pending')
        self.assertEqual(ConceptRevisionRequest.objects.count(), 0)
        self.assertEqual(concepts.latest_round(self.team, self.event).concepts[0]['title_review']['state'], 'accepted')
        with self.assertRaisesMessage(ValueError, 'title changed'):
            review_submission(self.team, self.event.label, 'CONCEPTS', 'accepted', '', self.first,
                file_id=file.pk, title_review_token='stale')

    def test_students_cannot_accept_and_faculty_cannot_submit_or_edit_titles(self):
        self.system()
        self.module()
        with self.assertRaises(PermissionError):
            workflow.team_action(self.team, self.event, self.pm, 'accept_title', 'c1')
        with self.assertRaises(PermissionError):
            workflow.team_action(self.team, self.event, self.first, 'submit_title', 'c1', 'Faculty replacement')
        with self.assertRaises(ValidationError):
            concepts.save_titles(self.team, self.event, self.titles(), actor=self.first)

    def test_shared_legacy_paper_obeys_same_title_and_combined_revision_rules(self):
        workflow.system_action(self.project, self.pm, 'submit_title', 'c1', 'System one')
        file = services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('system.pdf', b'%PDF-1.4 shared'))
        with self.assertRaises(ValidationError):
            services.review(self.project, self.first, file.pk, 'accepted')
        workflow.system_action(self.project, self.first, 'accept_title', 'c1')
        services.review(self.project, self.first, file.pk, 'accepted')
        services.review(self.project, self.first, file.pk, 'rejected', 'Change the shared concept.', revision_scope='title_and_paper')
        self.assertEqual(ConceptRevisionRequest.objects.count(), 1)
        self.assertFalse(services.latest(self.project).systems.get(key='c1').confirmed)

    def test_configured_shared_file_has_combined_revision_but_section_form_does_not(self):
        definitions = [fixtures.SharedDeliverableTests.definition(self, 'SYSTEMS', 'concepts'),
                       fixtures.SharedDeliverableTests.definition(self, 'FORM')]
        fixtures.SharedDeliverableTests.custom(self, definitions)
        self.system()
        for number, slot in [('SYSTEMS', 'c1:paper'), ('FORM', 'primary')]:
            profile = shared.resolve(self.team, self.event)
            shared.upload(self.team, self.event, self.pm, number, slot,
                SimpleUploadedFile('context.pdf', b'%PDF-1.4 context'), shared.review_token(profile))
        profile = shared.resolve(self.team, self.event)
        definition = next(d for d in profile['definitions'] if d['deliverable_id'] == 'FORM')
        file = shared.requirement_files(profile, definition)['primary']
        with self.assertRaisesMessage(ValidationError, 'does not have a reviewable concept title'):
            shared.review(self.team, self.event, self.first, 'FORM', 'primary', file['id'], False,
                'rejected', 'Revise both', shared.review_token(profile), revision_scope='title_and_paper')
        self.assertEqual(ConceptRevisionRequest.objects.count(), 0)
        definition = next(d for d in profile['definitions'] if d['deliverable_id'] == 'SYSTEMS')
        file = shared.requirement_files(profile, definition)['c1:paper']
        shared.review(self.team, self.event, self.first, 'SYSTEMS', 'c1:paper', file['id'], False,
            'rejected', 'Revise the system and paper.', shared.review_token(profile), revision_scope='title_and_paper')
        self.assertEqual(ConceptRevisionRequest.objects.get().scope, 'title_and_paper')
        self.assertFalse(services.latest(self.project).systems.get(key='c1').confirmed)

    def test_review_api_rejects_stale_title_snapshot_and_exposes_shared_request(self):
        self.system()
        self.module()
        self.accept_module()
        file = self.paper()
        self.client.force_authenticate(self.first)
        self.review(file, 'rejected', 'title_and_paper', 'Revise the concept scope.')
        state = concepts.payload(self.team, self.event, actor=self.first)
        response = self.client.post('/api/repository/deliverables/concepts/?response_mode=concept_titles', {
            'team_id': self.team.pk, 'stage_label': self.event.label, 'action': 'accept_title',
            'concept_key': 'c1', 'round_id': state['round_id'], 'review_token': 'stale'}, format='json')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(state['concepts'][0]['title_review']['revision_request']['id'], ConceptRevisionRequest.objects.get().pk)

    def test_legacy_preflight_is_read_only_and_explicit_upgrade_preserves_real_evidence(self):
        from django.contrib.auth import get_user_model
        from repository.title_reconciliation import reconcile
        current = services.latest(self.project)
        current.title_workflow_version = 1
        current.save(update_fields=['title_workflow_version'])
        services.save_system_titles(self.project, self.first, self.titles())
        concepts.save_titles(self.team, self.event, self.titles('Module'), actor=self.first)
        file = self.paper()
        self.review(file)
        admin = get_user_model().objects.create_user(username='workflow-upgrade-admin', role='admin')
        result = reconcile(admin, section_round=current.pk)
        current.refresh_from_db()
        self.assertEqual(current.title_workflow_version, 1)
        with self.assertRaises(ValidationError):
            reconcile(admin, section_round=current.pk, token='stale')
        reconcile(admin, section_round=current.pk, token=result['token'])
        current.refresh_from_db()
        file.refresh_from_db()
        self.assertEqual(current.title_workflow_version, 2)
        review = current.systems.get(key='c1').title_review
        self.assertEqual(review['state'], 'accepted')
        self.assertEqual(review['provenance'], 'legacy_confirmation')
        self.assertNotIn('reviewed_by', review)
        self.assertEqual(file.status, 'accepted')
        self.assertTrue(file.title_review_context)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class IndependentTitleFirstTests(APITestCase):
    def setUp(self):
        from repository.deliverables.test_submission_timing import faculty_review_setup
        faculty_review_setup(self)
        override = self.settings(DEFENSYS_TITLE_WORKFLOW_VERSION=2)
        override.enable()
        self.addCleanup(override.disable)
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        self.paper.file_policy = {'mode': 'concepts'}
        self.paper.save()

    def test_independent_title_acceptance_does_not_require_other_titles_or_papers(self):
        workflow.team_action(self.team, self.stage, self.student, 'submit_title', 'c1', 'Independent project')
        workflow.team_action(self.team, self.stage, self.adviser, 'accept_title', 'c1')
        state = concepts.payload(self.team, self.stage, actor=self.adviser)
        self.assertEqual(state['concepts'][0]['title_review']['state'], 'accepted')
        self.assertEqual(state['concepts'][1]['title_review']['state'], 'draft')
        self.assertFalse(self.team.deliverable_submissions.exists())

    def test_assigned_title_can_be_submitted_and_reviewed_without_unlocking_author_edits(self):
        self.team.concept_assignment = {'mode': 'assigned', 'assigned_title': 'Assigned concept', 'project_version': 1}
        self.team.save()
        current = concepts.get_round(self.team, self.stage)
        title = current.concepts[0]['title']
        workflow.team_action(self.team, self.stage, self.student, 'submit_title', 'c1', title)
        workflow.team_action(self.team, self.stage, self.adviser, 'accept_title', 'c1')
        state = concepts.payload(self.team, self.stage, actor=self.student)
        self.assertFalse(state['concepts'][0]['title_review']['can_edit'])
        self.assertEqual(state['concepts'][0]['title_review']['state'], 'accepted')
