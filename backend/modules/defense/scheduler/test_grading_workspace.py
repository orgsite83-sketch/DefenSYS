"""Panel workspace reads reuse shared ownership, permissions and frozen evidence."""
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from repository.section_concepts import test_hearing_flow as fixtures
from repository.section_concepts import services
from repository.section_concepts.models import SectionConceptPaper, SectionConceptRound
from grading.grades.services import submit_panelist_grade
from .grading_workspace import payload


class GradingWorkspaceTests(APITestCase):
    prepare_hearing = fixtures.CapstoneSharedHearingFlowTests.prepare_hearing

    def setUp(self):
        fixtures.CapstoneSharedHearingFlowTests.setUp(self)
        self.stage.qualifying_score = 75
        self.stage.save()
        self.project, self.schedule, self.grade, self.criterion = self.prepare_hearing()
        self.chair.is_panelist = True
        self.chair.save(update_fields=['is_panelist'])

    def workspace(self, actor=None):
        from repository.deliverables.models import ConceptRound
        hearing = ConceptRound.objects.select_related('section_round').get(schedule=self.schedule)
        return payload(self.schedule, hearing, actor or self.chair, [
            {'id': 987, 'slot_key': 'c2:paper', 'file_url': '/team-paper/', 'label': 'Module paper'},
            {'id': 988, 'slot_key': 'presentation', 'file_url': '/presentation/', 'label': 'Presentation'},
        ])

    def test_projection_pairs_shared_and_team_files_without_creating_records(self):
        from repository.deliverables.models import ConceptRound
        from repository.section_concepts.models import SharedDeliverableSet
        before = (ConceptRound.objects.count(), SharedDeliverableSet.objects.count(),
                  SectionConceptPaper.objects.count())
        value = self.workspace()
        self.assertEqual(len(value['shared_materials']), 3)
        self.assertEqual({f['candidate_key'] for f in value['shared_materials']}, {'c1', 'c2', 'c3'})
        self.assertTrue(all(f['material_scope'] == 'shared' for f in value['shared_materials']))
        self.assertEqual([f['candidate_key'] for f in value['team_materials']], ['c2', ''])
        self.assertTrue(value['shared_review']['can_decide'])
        self.assertEqual(value['shared_review']['teams'], [{'id': self.team.pk, 'name': self.team.name}])
        self.assertEqual(before, (ConceptRound.objects.count(), SharedDeliverableSet.objects.count(),
                                SectionConceptPaper.objects.count()))
        self.client.force_authenticate(self.chair)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(response.status_code, 200, response.data)
        assignment = next(row for row in response.data['teams'] if row['schedule_id'] == self.schedule.pk)
        self.assertEqual(len(assignment['grading_workspace']['shared_materials']), 3)

    def test_regular_assigned_panelist_reads_but_cannot_decide(self):
        from django.contrib.auth import get_user_model
        from .models import SchedulePanelist
        actor = get_user_model().objects.create_user(username='workspace-panel', role='faculty')
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=actor)
        value = self.workspace(actor)
        self.assertEqual(len(value['shared_materials']), 3)
        self.assertFalse(value['shared_review']['can_decide'])
        self.assertIn('common panel chair', value['shared_review']['decision_unavailable_reason'])

    def test_external_panelist_reads_only_the_assigned_hearing(self):
        from authentication_access_control.guest_authentication import GuestPanelistPrincipal
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.create(guest_name='Workspace reviewer', defense_schedule=self.schedule)
        invitation.schedules.add(self.schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk),
            'guest_code': invitation.code}, invitation=invitation)
        self.client.force_authenticate(guest)
        response = self.client.get('/api/defense/schedules/guest-assignments/')
        self.assertEqual(response.status_code, 200, response.data)
        workspace = response.data['teams'][0]['grading_workspace']
        self.assertEqual(len(workspace['shared_materials']), 3)
        self.assertFalse(workspace['shared_review']['can_decide'])
        for file in workspace['shared_materials']:
            download = self.client.get(file['file_url'])
            self.assertEqual(download.status_code, 200)
            self.assertTrue(b''.join(download.streaming_content).startswith(b'%PDF'))
        self.assertEqual(self.workspace(self.student).get('shared_review'), None)

    def test_missing_shared_slot_retains_its_requirement_and_candidate(self):
        SectionConceptPaper.objects.filter(concept__round=services.latest(self.project), concept__key='c2').delete()
        value = self.workspace()
        missing = next(f for f in value['shared_materials'] if f['candidate_key'] == 'c2')
        self.assertTrue(missing['missing'])
        self.assertTrue(missing['label'])
        self.assertNotIn('file_url', missing)

    def test_non_material_and_post_defense_shared_files_are_excluded_even_for_admin(self):
        hearing = services.latest(self.project)
        definitions = hearing.shared_requirements_snapshot
        for definition in definitions:
            definition['is_defense_material'] = False
        hearing.shared_requirements_snapshot = definitions
        hearing.save(update_fields=['shared_requirements_snapshot'])
        value = self.workspace(self.admin)
        self.assertEqual(value['shared_materials'], [])
        self.assertFalse(value['shared_materials_configured'])
        for definition in definitions:
            definition['is_defense_material'] = definition['deliverable_type'] == 'post'
        hearing.shared_requirements_snapshot = definitions
        hearing.save(update_fields=['shared_requirements_snapshot'])
        self.assertEqual(self.workspace(self.admin)['shared_materials'], [])

    def test_generic_shared_checklist_without_concept_project_stays_evaluation_only(self):
        from defense.stages.models import DefenseStage
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from repository.section_concepts.models import SharedDeliverableSet
        section = self.project.section
        section.system_name, section.project_manager = 'Assigned section platform', self.student
        section.save(update_fields=['system_name', 'project_manager'])
        stage = DefenseStage.objects.create(label='Later project presentation',
            display_order=self.stage.display_order + 1, concept_config={}, shared_deliverables=[{
                'deliverable_id': 'SHARED_DECK', 'label': 'System presentation',
                'deliverable_type': 'pre', 'is_defense_material': True,
                'file_policy': {'mode': 'single'},
            }])
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=stage, scheduled_date=self.schedule.scheduled_date,
            start_time='13:00', room='Generic shared hearing')
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.chair, is_chair=True)
        before = (SectionConceptRound.objects.count(), SharedDeliverableSet.objects.count())
        value = payload(schedule, None, self.chair, [])
        self.assertTrue(value['shared_materials_configured'])
        self.assertEqual(value['shared_materials'][0]['label'], 'System presentation')
        self.assertEqual(value['shared_materials'][0]['candidate_key'], '')
        self.assertNotIn('shared_review', value)
        self.assertEqual(before, (SectionConceptRound.objects.count(), SharedDeliverableSet.objects.count()))

    def test_later_stage_reads_its_shared_files_instead_of_the_selected_systems_origin_snapshot(self):
        from defense.stages.models import DefenseStage
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from repository.section_concepts import shared_deliverables as shared
        from repository.section_concepts.models import SharedDeliverableFile, SharedDeliverableSet

        self.decide()
        origin = services.latest(self.project)
        origin_number = origin.decision_snapshot['shared_documents'][0]['deliverable_id']
        stage = DefenseStage.objects.create(label='Later shared project proposal',
            display_order=self.stage.display_order + 1, concept_config={}, shared_deliverables=[
                {'deliverable_id': 'SHARED_DECK', 'label': 'Pitch Deck',
                 'deliverable_type': 'pre', 'is_defense_material': True,
                 'file_format': 'presentation', 'file_policy': {'mode': 'single'}},
                # Reusing a requirement ID must not expose the origin's papers.
                {'deliverable_id': origin_number, 'label': 'Current stage paper',
                 'deliverable_type': 'pre', 'is_defense_material': True,
                 'file_policy': {'mode': 'single'}},
            ])
        profile = shared.resolve(self.team, stage)
        self.assertIsNone(profile['current_project'])
        self.assertEqual(profile['round'].pk, origin.pk)
        shared.upload(self.team, stage, self.student, 'SHARED_DECK', 'primary',
            SimpleUploadedFile('shared-system-pitch.pptx', b'presentation content'),
            shared.review_token(profile))
        deck = SharedDeliverableFile.objects.get(deliverable_id='SHARED_DECK')
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=stage, scheduled_date=self.schedule.scheduled_date,
            start_time='13:00', room='Later shared hearing')
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.chair, is_chair=True)
        before = (SectionConceptRound.objects.count(), SharedDeliverableSet.objects.count(),
                  SharedDeliverableFile.objects.count())

        value = payload(schedule, None, self.chair, [])
        uploaded = next(f for f in value['shared_materials'] if f['deliverable_id'] == 'SHARED_DECK')
        self.assertNotIn('missing', uploaded)
        self.assertEqual(uploaded['id'], deck.pk)
        self.assertEqual(uploaded['file_name'], deck.file_name)
        missing = [f for f in value['shared_materials'] if f['deliverable_id'] == origin_number]
        self.assertEqual(len(missing), 1)
        self.assertEqual(missing[0]['slot_key'], 'primary')
        self.assertTrue(missing[0]['missing'])
        self.assertNotIn('shared_review', value)
        self.assertEqual(before, (SectionConceptRound.objects.count(), SharedDeliverableSet.objects.count(),
                                SharedDeliverableFile.objects.count()))
        self.client.force_authenticate(self.chair)
        response = self.client.get(uploaded['file_url'])
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'presentation content')

    def decide(self):
        for key in services.KEYS:
            submit_panelist_grade(self.schedule, self.grade,
                [{'criterion_id': self.criterion.pk, 'score': 8}], panelist=self.chair, concept_key=key)
        services.decide(self.project, self.chair,
            [{'key': key, 'decision': 'approved' if key == 'c2' else 'not_selected'}
             for key in services.KEYS], 'approved', '')

    def test_recorded_hearing_uses_its_captured_shared_file_versions(self):
        self.decide()
        old = SectionConceptPaper.objects.get(concept__round=services.latest(self.project),
                                             concept__key='c2', purpose='proposal', is_current=True)
        old.is_current = False
        old.save(update_fields=['is_current'])
        replacement = SectionConceptPaper.objects.create(concept=old.concept, purpose='proposal',
            revision=old.revision + 1, is_current=True, status='accepted', uploaded_by=self.student,
            file_name='later-version.pdf', file=SimpleUploadedFile('later-version.pdf', b'%PDF-1.4 later'))
        files = self.workspace()['shared_materials']
        self.assertIn(old.pk, [f['id'] for f in files])
        self.assertNotIn(replacement.pk, [f['id'] for f in files])
        self.assertFalse(self.workspace()['shared_review']['can_decide'])

    def test_old_schedule_does_not_switch_to_new_section_round(self):
        original = services.latest(self.project)
        SectionConceptRound.objects.create(project=self.project, number=original.number + 1)
        value = self.workspace()['shared_review']
        self.assertEqual(value['round_id'], original.pk)
        self.assertEqual([s['title'] for s in value['systems']], ['System c1', 'System c2', 'System c3'])
        self.assertFalse(value['can_decide'])
