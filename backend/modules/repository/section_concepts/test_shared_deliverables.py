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

    def test_one_configuration_synchronizes_team_and_pm_definitions_without_combining_files(self):
        team = self.definition('D1', label='Team and system paper', is_defense_material=True)
        pm = self.definition('SHARED_D1', label='Old label', team_deliverable_id='D1', required=False)
        definitions = validate_shared_deliverables([pm], {}, [team])
        self.assertEqual(definitions[0]['team_deliverable_id'], 'D1')
        self.assertEqual(definitions[0]['label'], team['label'])
        self.assertTrue(definitions[0]['required'])
        self.assertTrue(definitions[0]['is_defense_material'])
        self.assertEqual(definitions[0]['deliverable_id'], 'SHARED_D1')
        self.assertEqual(pm['label'], 'Old label')
        with self.assertRaises(ValidationError):
            validate_shared_deliverables([pm], {}, [])
        with self.assertRaises(ValidationError):
            validate_shared_deliverables([pm, {**pm, 'deliverable_id': 'SHARED_D2'}], {}, [team])

    def test_linked_team_and_pm_requirement_round_trips_capstone_setup(self):
        from defense.stages.serializers import DefenseStageWriteSerializer, DefenseStageSerializer
        serializer = DefenseStageWriteSerializer(data={
            'label': 'Unified requirements',
            'deliverables': [self.definition('D1', label='Concept Paper')],
            'shared_deliverables': [self.definition('SHARED_D1', team_deliverable_id='D1')],
        })
        self.assertTrue(serializer.is_valid(), serializer.errors)
        stage = serializer.save()
        result = DefenseStageSerializer(stage).data
        self.assertEqual(len(result['deliverables']), 1)
        self.assertEqual(result['shared_deliverables'][0]['team_deliverable_id'], 'D1')
        self.assertEqual(result['shared_deliverables'][0]['label'], 'Concept Paper')
        update = DefenseStageWriteSerializer(stage, data={
            'deliverables': [self.definition('D1', label='Updated requirement')],
        }, partial=True)
        self.assertTrue(update.is_valid(), update.errors)
        updated = update.save()
        self.assertEqual(updated.shared_deliverables[0]['label'], 'Updated requirement')

    def test_pm_only_automatic_papers_are_not_recreated_as_team_requirements(self):
        from defense.document_policy import with_concept_papers
        from defense.stages.serializers import DefenseStageWriteSerializer
        papers = with_concept_papers([], {'enabled': True})
        shared_papers = [{**row, 'deliverable_id': f'SHARED_D{index}'} for index, row in enumerate(papers, 1)]
        serializer = DefenseStageWriteSerializer(data={
            'label': 'PM concept papers only', 'concept_config': {'enabled': True},
            'deliverables': [], 'shared_deliverables': shared_papers,
        })
        self.assertTrue(serializer.is_valid(), serializer.errors)
        stage = serializer.save()
        self.assertFalse(stage.deliverables.exists())
        self.assertEqual(len(stage.shared_deliverables), 2)
        self.assertEqual(with_concept_papers([], stage.concept_config, shared_items=stage.shared_deliverables), [])

    def test_linked_team_and_pm_requirement_round_trips_pit_setup(self):
        from defense.scheduler.pit_config import upsert_pit_event_config, pit_event_config_payload
        event = upsert_pit_event_config(semester=self.semester, year_level=self.team.year_level,
            event_name='Unified later event', user=self.admin,
            deliverables=[self.definition('D1', label='System and module report')],
            shared_deliverables=[self.definition('SHARED_D1', team_deliverable_id='D1')])
        state = pit_event_config_payload(event)
        self.assertEqual(len(state['deliverables']), 1)
        self.assertEqual(state['shared_deliverables'][0]['team_deliverable_id'], 'D1')
        self.assertEqual(state['shared_deliverables'][0]['label'], 'System and module report')

    def test_team_and_pm_files_require_their_own_submissions_and_acceptance(self):
        from defense.scheduler.models import PitEventDeliverable
        from repository.deliverables.services import upsert_submission, review_submission, required_complete
        definition = self.definition('D1', label='Team and system report')
        shared_definitions = validate_shared_deliverables([
            self.definition('SHARED_D1', team_deliverable_id='D1')], {}, [definition])
        event = self.next_event(shared_definitions)
        PitEventDeliverable.objects.create(pit_event_config=event, **definition)
        self.upload('SHARED_D1', context=event)
        self.accept('SHARED_D1', context=event)
        self.assertTrue(self.state(context=event)['pre_complete'])
        self.assertFalse(required_complete(self.team, event.event_name))
        submission = upsert_submission(self.team, event.event_name, 'D1', 'team-report.pdf',
            '20 B', self.team.leader, file=SimpleUploadedFile('team-report.pdf', b'%PDF-1.4 team evidence'))
        self.assertFalse(required_complete(self.team, event.event_name))
        review_submission(self.team, event.event_name, 'D1', 'accepted', '', self.first,
            file_id=submission.files.get(is_current=True).pk)
        self.assertTrue(required_complete(self.team, event.event_name))
        self.assertFalse(required_complete(self.module_team, event.event_name))

    def test_pm_only_requirements_do_not_assign_uploads_to_an_independent_team(self):
        from defense.stages.serializers import DefenseStageWriteSerializer
        from student_teams.models import StudentTeam
        from repository.deliverables.services import stage_deliverables_configured, required_complete
        team = StudentTeam.objects.create(name='Independent capstone', semester=self.semester,
            leader=self.team.leader, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year', section='INDEPENDENT')
        serializer = DefenseStageWriteSerializer(data={'label':'PM forms only', 'deliverables':[],
            'shared_deliverables':[self.definition('PM_FORM')]})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        stage = serializer.save()
        self.assertIsNone(shared.resolve(team, stage))
        self.assertTrue(stage_deliverables_configured(team, stage.label))
        self.assertTrue(required_complete(team, stage.label))

    def test_malformed_shared_settings_stay_validation_errors(self):
        from defense.stages.serializers import DefenseStageWriteSerializer
        for definitions in ([None], 'invalid', [self.definition(file_policy=[])]):
            serializer = DefenseStageWriteSerializer(data={'label':'Invalid shared setup',
                'concept_config':{'enabled':True}, 'shared_deliverables':definitions})
            self.assertFalse(serializer.is_valid())
            self.assertIn('shared_deliverables', serializer.errors)

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
