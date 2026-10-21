"""Import setup regressions; APITestCase always uses the isolated test DB."""
from rest_framework.test import APITestCase

from . import tests as capstone_fixtures
from . import test_roster_workspace as pit_fixtures
from .models import StudentTeam, PITRosterTeamDetails
from .formation_views import setup_tasks
from .roster_workspace import setup_tasks as event_tasks


class CapstoneImportSetupTests(APITestCase):
    setUp = capstone_fixtures.StudentTeamApiTests.setUp
    _activate_capstone_intake_semester = capstone_fixtures.StudentTeamApiTests._activate_capstone_intake_semester

    def test_each_missing_name_title_combination_preserves_supplied_data(self):
        self._activate_capstone_intake_semester()
        for name, title in [('', 'Campus Navigation'), ('Named team', ''), ('', ''), ('Named team', 'Supplied title')]:
            with self.subTest(name=name, title=title):
                row = {'team_name': name, 'project_title': title, 'group_key': 'file0/table0/row5',
                    'level': StudentTeam.LEVEL_3_CAPSTONE, 'member_ids': [self.student_1.username],
                    'leader_id': self.student_1.username}
                preview = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
                self.assertEqual(preview.status_code, 200, preview.data)
                self.assertTrue(preview.data['rows'][0]['ready'], preview.data)
                self.assertFalse(StudentTeam.objects.exists())
                result = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
                self.assertEqual(result.data['created_count'], 1, result.data)
                team = StudentTeam.objects.get()
                self.assertEqual(team.setup_pending, not bool(name))
                self.assertEqual(team.project_pending, not bool(title))
                self.assertEqual(team.project_title, title)
                if name:
                    self.assertEqual(team.name, name)
                else:
                    self.assertTrue(team.name.startswith('Unnamed team '))
                    self.client.force_authenticate(self.student_2)
                    self.assertEqual(setup_tasks(self.student_2), [])
                    denied = self.client.patch(f'/api/teams/{team.pk}/setup/', {'name': 'Stolen'}, format='json')
                    self.assertEqual(denied.status_code, 404)
                    self.client.force_authenticate(self.student_1)
                    tasks = setup_tasks(self.student_1)
                    self.assertTrue(tasks[0]['needs_name'])
                    if title:
                        self.assertEqual(tasks[0]['concept_tasks'], [])
                    saved = self.client.patch(f'/api/teams/{team.pk}/setup/', {'name': 'Leader choice'}, format='json')
                    self.assertEqual(saved.status_code, 200, saved.data)
                    team.refresh_from_db()
                    self.assertFalse(team.setup_pending)
                    self.assertEqual(team.project_pending, not bool(title))
                    self.assertEqual(team.project_title, title)
                StudentTeam.objects.all().delete()
                self.client.force_authenticate(self.admin)


class PitImportSetupTests(APITestCase):
    setUp = pit_fixtures.RosterWorkspaceTests.setUp
    body = pit_fixtures.RosterWorkspaceTests.body
    preview = pit_fixtures.RosterWorkspaceTests.preview
    apply = pit_fixtures.RosterWorkspaceTests.apply

    def rows(self):
        return [{'team_name': '', 'project_title': title, 'section': 'BSIT-2A',
            'member_ids': [self.students[i].username], 'leader_id': self.students[i].username}
            for i, title in enumerate(['Retained title', ''])]

    def test_current_unnamed_teams_get_distinct_identities_and_leader_naming_tasks(self):
        preview = self.preview(operation='import', teams=self.rows())
        self.assertEqual([r['display_name'] for r in preview['teams']], ['Unnamed team 1', 'Unnamed team 2'])
        self.assertFalse(StudentTeam.objects.exists())
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        again = self.apply(preview)
        self.assertEqual(again.data['team_ids'], result.data['team_ids'])
        teams = list(StudentTeam.objects.order_by('pk'))
        self.assertNotEqual(teams[0].name, teams[1].name)
        self.assertEqual(teams[0].project_title, 'Retained title')
        self.assertFalse(teams[0].project_pending)
        self.assertTrue(teams[1].project_pending)
        self.assertEqual([t['id'] for t in setup_tasks(self.students[0])], [teams[0].pk])
        self.assertEqual(event_tasks(self.students[0]), [])
        self.client.force_authenticate(self.students[0])
        response = self.client.patch(f'/api/teams/{teams[0].pk}/setup/', {'name': 'Chosen name'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        teams[0].refresh_from_db()
        self.assertEqual(teams[0].project_title, 'Retained title')
        self.assertEqual(PITRosterTeamDetails.objects.get(team=teams[0], event=None).name, 'Chosen name')
        self.assertEqual(setup_tasks(self.students[0]), [])

    def test_event_import_opens_only_missing_setup_and_preserves_supplied_title(self):
        rows = self.rows()
        rows.append({'team_name': 'Complete team', 'project_title': 'Complete title',
            'member_ids': [self.students[2].username], 'leader_id': self.students[2].username})
        preview = self.preview(operation='import', event_id=self.event.pk, teams=rows)
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        team = StudentTeam.objects.get(pk=result.data['team_ids'][0])
        self.assertEqual(setup_tasks(self.students[0]), [])
        tasks = event_tasks(self.students[0])
        self.assertEqual(len(tasks), 1)
        self.assertEqual(tasks[0]['project_title'], 'Retained title')
        self.assertEqual(event_tasks(self.students[2]), [])
        self.client.force_authenticate(self.students[0])
        saved = self.client.patch(f'/api/teams/{team.pk}/events/{self.event.pk}/setup/',
            {'name': 'Event choice', 'revision': tasks[0]['revision']}, format='json')
        self.assertEqual(saved.status_code, 200, saved.data)
        team.refresh_from_db()
        self.assertFalse(team.setup_pending)
        self.assertEqual(team.project_title, 'Retained title')

    def test_shared_sheet_metadata_is_reviewed_without_writes_then_applied_atomically(self):
        from .models import SectionAssignment
        rows = self.rows()
        rows[0].update(system_name='Campus Services', project_manager=self.students[0].username)
        preview = self.preview(operation='import', teams=rows)
        self.assertFalse(SectionAssignment.objects.exists())
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        assignment = SectionAssignment.objects.get(section='BSIT-2A')
        self.assertEqual(assignment.system_name, 'Campus Services')
        self.assertEqual(assignment.project_manager_id, self.students[0].pk)

    def test_shared_manager_from_another_section_is_rejected_before_writes(self):
        rows = self.rows()
        rows[0].update(system_name='Campus Services', project_manager=self.students[10].username)
        result = self.client.post('/api/teams/rosters/preview/', self.body(operation='import', teams=rows), format='json')
        self.assertEqual(result.status_code, 400, result.data)
        self.assertFalse(StudentTeam.objects.exists())

    def test_section_concept_policy_is_enforced_for_roster_imports(self):
        from .models import SectionAssignment
        from .concept_policy import context_key
        SectionAssignment.objects.create(semester=self.term, year_level='2nd Year', section='BSIT-2A',
            concept_policies={context_key(self.event): {'mode': 'proposals', 'required_count': 2}})
        result = self.client.post('/api/teams/rosters/preview/', self.body(operation='import',
            event_id=self.event.pk, teams=self.rows()), format='json')
        self.assertEqual(result.status_code, 400, result.data)
        self.assertFalse(StudentTeam.objects.exists())
