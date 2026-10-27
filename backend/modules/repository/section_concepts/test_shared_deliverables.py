from copy import deepcopy
import tempfile
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from defense.shared_deliverables import validate_shared_deliverables
from defense.scheduler.models import PitEventGradingConfig
from student_teams.models import PITEventRoster
from . import tests as fixtures
from .models import SharedDeliverableSet, SharedDeliverableFile, SectionConceptPaper
from . import services, shared_deliverables as shared


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedDeliverableTests(APITestCase):
    rubric, data, slot = fixtures.SharedSystemConceptTests.rubric, fixtures.SharedSystemConceptTests.data, fixtures.SharedSystemConceptTests.slot
    configure, titles, prepare_shared = fixtures.SharedSystemConceptTests.configure, fixtures.SharedSystemConceptTests.titles, fixtures.SharedSystemConceptTests.prepare_shared

    def setUp(self):
        self.media = tempfile.TemporaryDirectory()
        self.addCleanup(self.media.cleanup)
        self.setting = self.settings(MEDIA_ROOT=self.media.name)
        self.setting.enable()
        self.addCleanup(self.setting.disable)
        fixtures.SharedSystemConceptTests.setUp(self)

    def custom(self, definitions):
        definitions = validate_shared_deliverables(definitions, self.event.concept_config)
        self.event.shared_deliverables = definitions
        self.event.save(update_fields=['shared_deliverables'])
        hearing = services.latest(self.project)
        hearing.shared_requirements_snapshot = definitions
        hearing.save(update_fields=['shared_requirements_snapshot'])
        return definitions

    def definition(self, number='ADMIN', mode='single', dtype='pre', **changes):
        return {'deliverable_id': number, 'label': number, 'deliverable_type': dtype,
            'required': True, 'file_format': 'pdf', 'file_policy': {'mode': mode}, **changes}

    def state(self, actor=None, context=None):
        return shared.payload(shared.resolve(self.team, context or self.event), actor or self.pm)

    def upload(self, number='ADMIN', slot='primary', context=None, actor=None, name='form.pdf', token=None):
        context = context or self.event
        return shared.upload(self.team, context, actor or self.pm, number, slot,
            SimpleUploadedFile(name, b'%PDF-1.4 test evidence'), token or self.state(context=context)['review_token'])

    def accept(self, number='ADMIN', slot='primary', context=None, status='accepted', feedback=''):
        context = context or self.event
        state = self.state(self.first, context)
        definition = next(row for row in state['requirements'] if row['deliverable_id'] == number)
        file = next(row['file'] for row in definition['documents'] if row['key'] == slot)
        return shared.review(self.team, context, self.first, number, slot, file['id'], file['legacy'],
            status, feedback, state['review_token'])

    def test_mixed_per_concept_and_once_per_section_documents(self):
        self.custom([self.definition(), self.definition('DECK', 'concepts', file_policy={
            'mode': 'concepts', 'slots': [{'key': 'deck', 'label': 'Pitch deck', 'required': True, 'file_format': 'presentation'}]})])
        state = self.state()
        self.assertEqual([len(row['documents']) for row in state['requirements']], [1, 3])
        self.assertEqual(SharedDeliverableSet.objects.count(), 0)
        self.upload()
        for key in services.KEYS:
            self.upload('DECK', f'{key}:deck')
        other = shared.payload(shared.resolve(self.module_team, self.event), self.module_team.leader)
        self.assertEqual(len(other['requirements'][0]['documents']), 1)
        self.assertEqual(other['requirements'][0]['documents'][0]['file']['id'],
            self.state()['requirements'][0]['documents'][0]['file']['id'])
        self.assertEqual(SharedDeliverableSet.objects.count(), 1)
        self.assertEqual(SharedDeliverableFile.objects.count(), 4)
        self.accept()
        for key in services.KEYS:
            self.accept('DECK', f'{key}:deck')
        services.save_system_titles(self.project, self.first, self.titles())
        self.assertTrue(services.shared_clearance(services.latest(self.project)))
        self.assertFalse(services.latest(self.project).module_rounds.exclude(endorsed_at=None).exists())

    def test_upload_permissions_stale_tokens_and_formats(self):
        self.custom([self.definition()])
        token = self.state()['review_token']
        with self.assertRaises(PermissionError):
            self.upload(actor=self.module_team.leader)
        with self.assertRaises(ValidationError):
            self.upload(name='form.zip')
        self.upload(token=token)
        with self.assertRaises(ValidationError):
            self.upload(token=token)
        with self.assertRaises(PermissionError):
            profile = shared.resolve(self.team, self.event)
            row = self.state()['requirements'][0]['documents'][0]['file']
            shared.review(self.team, self.event, self.pm, 'ADMIN', 'primary', row['id'], False,
                'accepted', '', shared.review_token(profile))

    def test_corrections_preserve_versions_and_accepted_files_lock(self):
        self.custom([self.definition()])
        self.upload()
        self.accept()
        with self.assertRaises(ValidationError):
            self.upload()
        self.accept(status='rejected', feedback='Update the signature.')
        self.upload(name='corrected.pdf')
        files = SharedDeliverableFile.objects.order_by('revision')
        self.assertEqual(list(files.values_list('revision', 'is_current')), [(1, False), (2, True)])
        state = self.state()
        self.assertEqual(len(state['requirements'][0]['history']), 1)
        self.assertFalse(state['pre_complete'])

    def test_legacy_papers_are_adapted_without_copying_or_initializing_records(self):
        self.prepare_shared()
        originals = set(SectionConceptPaper.objects.values_list('pk', flat=True))
        self.client.force_authenticate(self.pm)
        response = self.client.get('/api/repository/section-concepts/shared-deliverables/',
            {'team_id': self.team.pk, 'stage_label': self.event.label})
        self.assertEqual(response.status_code, 200, response.data)
        requirement = response.data['shared_deliverables']['requirements'][0]
        self.assertEqual({d['file']['id'] for d in requirement['documents']}, originals)
        self.assertTrue(all(d['file']['legacy'] for d in requirement['documents']))
        self.assertEqual(SharedDeliverableSet.objects.count(), 0)
        self.assertEqual(set(SectionConceptPaper.objects.values_list('pk', flat=True)), originals)

    def test_attachment_limits_are_group_wide_and_every_file_needs_review(self):
        self.custom([self.definition(mode='multiple', file_policy={'mode': 'multiple', 'min_files': 1, 'max_files': 2})])
        self.upload(slot='')
        self.upload(slot='')
        with self.assertRaises(ValidationError):
            self.upload(slot='')
        state = self.state()
        for document in state['requirements'][0]['documents']:
            self.accept(slot=document['key'])
        self.assertTrue(self.state()['pre_complete'])

    def next_event(self, definitions):
        hearing = services.latest(self.project)
        hearing.selected_key, hearing.verdict = 'c2', 'approved'
        hearing.save(update_fields=['selected_key', 'verdict'])
        hearing.systems.filter(key='c2').update(title='Approved shared system')
        event = PitEventGradingConfig.objects.create(semester=self.semester, year_level=self.team.year_level,
            event_name='Later shared showcase', shared_deliverables=definitions)
        roster = PITEventRoster.objects.create(event=event, section=self.team.section, source='custom')
        roster.teams.set([self.team, self.module_team])
        return event

    def test_later_event_reuses_selected_system_with_fresh_evidence(self):
        self.custom([self.definition()])
        self.upload()
        later = self.next_event([self.definition()])
        later_state = self.state(context=later)
        self.assertEqual(later_state['systems'], [{'key': 'c2', 'title': 'Approved shared system'}])
        self.assertEqual(services.team_display(self.team, later.label)['system_name'], 'Approved shared system')
        self.assertIsNone(later_state['requirements'][0]['documents'][0]['file'])
        self.upload(context=later)
        self.assertEqual(SharedDeliverableSet.objects.count(), 2)

    def test_post_defense_gate_then_shared_archive_and_privacy(self):
        later = self.next_event([self.definition(dtype='post', is_restricted=True)])
        with self.assertRaises(PermissionError):
            self.upload(context=later)
        with patch('repository.deliverables.services.post_defense_ready', return_value=True):
            self.upload(context=later)
            self.assertFalse(self.state(context=later)['post_complete'])
            self.accept(context=later)
            self.assertTrue(self.state(context=later)['post_complete'])
        from repository.project_archive.shared_concepts import shared_final_entries
        entries = shared_final_entries({'scope': 'pit_lead', 'pit_year_level': self.team.year_level})
        self.assertEqual(len(entries), 1)
        self.assertTrue(entries[0]['is_restricted_archive'])
        self.assertEqual(shared_final_entries({'scope': 'pit_lead', 'pit_year_level': '3rd Year'}), [])

    def test_private_files_use_same_policy_for_both_media_routes(self):
        self.custom([self.definition()])
        self.upload()
        file = SharedDeliverableFile.objects.get()
        user = get_user_model().objects.create_user(username='unrelated-shared-reader', role='student')
        routes = [f'/api/repository/section-concepts/shared-deliverables/files/{file.pk}/',
                  f'/media/{file.file.name}', f'/api/media/files/{file.file.name}']
        self.client.force_authenticate(user)
        for route in routes:
            self.assertEqual(self.client.get(route).status_code, 404, route)
        self.client.force_authenticate(self.module_team.leader)
        for route in routes:
            response = self.client.get(route)
            self.assertEqual(response.status_code, 200, route)
            # Closing the response emits request_finished and closes Django's
            # transactional test connection. Close only its streamed file here.
            if response.file_to_stream:
                response.file_to_stream.close()

    def test_changing_setup_does_not_rewrite_captured_hearing_requirements(self):
        original = deepcopy(services.latest(self.project).shared_requirements_snapshot)
        self.event.shared_deliverables = [self.definition()]
        self.event.save(update_fields=['shared_deliverables'])
        self.assertEqual(shared.resolve(self.team, self.event)['definitions'], original)

    def test_configuration_rejects_duplicate_ids_and_per_concept_mode_without_selection(self):
        with self.assertRaises(ValidationError):
            validate_shared_deliverables([self.definition(), self.definition()], {})
        with self.assertRaises(ValidationError):
            validate_shared_deliverables([self.definition(mode='concepts')], {})

    def test_configured_shared_only_event_and_setup_lock(self):
        from defense.scheduler.pit_config import upsert_pit_event_config, pit_event_config_payload, check_pit_event_locked
        later = self.next_event([self.definition()])
        from repository.deliverables.services import stage_deliverables_configured
        self.assertTrue(stage_deliverables_configured(self.team, later.label))
        self.upload(context=later)
        self.assertTrue(check_pit_event_locked(later)[0])
        with self.assertRaises(ValidationError):
            upsert_pit_event_config(semester=self.semester, event_name=later.event_name,
                year_level=later.year_level, config_id=later.pk, user=self.admin,
                shared_deliverables=[self.definition('CHANGED')])
        self.assertEqual(pit_event_config_payload(later)['shared_deliverables'][0]['deliverable_id'], 'ADMIN')

    def test_capstone_setup_round_trip_and_invalid_config_report_validation_errors(self):
        from defense.stages.serializers import DefenseStageWriteSerializer, DefenseStageSerializer
        serializer = DefenseStageWriteSerializer(data={'label': 'Shared project proposal', 'shared_deliverables': [self.definition()]})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        stage = serializer.save()
        self.assertEqual(DefenseStageSerializer(stage).data['shared_deliverables'][0]['label'], 'ADMIN')
        invalid = DefenseStageWriteSerializer(data={'label': 'Invalid shared stage', 'concept_config': [],
            'shared_deliverables': [self.definition()]})
        self.assertFalse(invalid.is_valid())
        self.assertIn('concept_config', invalid.errors)

    def test_upload_endpoint_returns_configured_shared_cards_and_preserves_scope(self):
        self.custom([self.definition()])
        self.client.force_authenticate(self.pm)
        response = self.client.post('/api/repository/section-concepts/shared-deliverables/', {
            'team_id': self.team.pk, 'stage_label': self.event.label,
            'review_token': self.state()['review_token'], 'deliverable_id': 'ADMIN', 'slot_key': 'primary',
            'file': SimpleUploadedFile('form.pdf', b'%PDF-1.4 shared form')}, format='multipart')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['shared_deliverables']['requirements'][0]['status'], 'pending')
        self.client.force_authenticate(self.module_team.leader)
        response = self.client.post('/api/repository/section-concepts/shared-deliverables/', {
            'team_id': self.module_team.pk, 'stage_label': self.event.label,
            'review_token': self.state()['review_token'], 'deliverable_id': 'ADMIN', 'slot_key': 'primary',
            'file': SimpleUploadedFile('form.pdf', b'%PDF-1.4 shared form')}, format='multipart')
        self.assertIn(response.status_code, (403, 404), response.data)
        self.assertEqual(SharedDeliverableFile.objects.count(), 1)

    def test_legacy_revision_clearance_keeps_its_original_snapshot_contract(self):
        self.prepare_shared()
        hearing = services.latest(self.project)
        original = services.snapshot(hearing)
        original.pop('shared_documents')
        hearing.verdict = 'approved_with_revisions'
        hearing.revisions_cleared_at = timezone.now()
        hearing.endorsement_snapshot = original
        hearing.save(update_fields=['verdict', 'revisions_cleared_at', 'endorsement_snapshot'])
        self.assertTrue(services.shared_clearance(hearing))

    def test_legacy_acknowledgment_hash_is_preserved_for_unchanged_content(self):
        from . import acknowledgments
        from .models import SectionConceptAcknowledgment
        self.prepare_shared()
        hearing = services.latest(self.project)
        original = acknowledgments.version_snapshot(hearing)
        original.pop('shared_documents')
        original.pop('shared_available')
        SectionConceptAcknowledgment.objects.create(round=hearing, faculty=self.second,
            fingerprint=acknowledgments.fingerprint(original), snapshot=original)
        self.assertTrue(acknowledgments.acknowledged(hearing, self.second.pk))

    def test_archived_shared_final_remains_readable_after_new_team_project_versions(self):
        from repository.deliverables.concept_completion import shared_final_complete
        self.prepare_shared()
        hearing = services.latest(self.project)
        hearing.selected_key, hearing.verdict = 'c2', 'approved'
        hearing.save(update_fields=['selected_key', 'verdict'])
        SectionConceptPaper.objects.create(concept=hearing.systems.get(key='c2'), purpose='final',
            file=SimpleUploadedFile('archived.pdf', b'%PDF-1.4 archived shared final'), file_name='archived.pdf',
            uploaded_by=self.pm, status='accepted')
        for team in (self.team, self.module_team):
            team.project_version += 1
            team.save(update_fields=['project_version'])
        self.assertTrue(shared_final_complete(hearing))
        profile = shared.for_round(hearing)
        self.assertTrue(profile['historical'])
        state = shared.payload(profile, self.pm)
        archived = next(row for row in state['requirements'] if row['deliverable_id'] == 'SHARED_FINAL')
        self.assertEqual(archived['documents'][0]['file']['file_name'], 'archived.pdf')
        self.assertFalse(archived['documents'][0]['can_upload'])
