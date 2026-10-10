from django.contrib.auth import get_user_model
from unittest.mock import patch, MagicMock
from datetime import timedelta
import tempfile
from pathlib import Path
from io import StringIO, BytesIO
from django.core.files.base import ContentFile
from django.test import override_settings
from django.core.management import call_command
from rest_framework.test import APITestCase, APIClient

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from defense.scheduler.models import PitEventGradingConfig
from grading.grades.models import TeamGrade, GradeBreakdown, PeerEvaluationSubmission
from grading.rubrics.models import Rubric, RubricCriterion
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from repository.archive.models import ArchiveEntry
from student_teams.models import StudentTeam, TeamMembership


class CurriculumExplorerTests(APITestCase):
    def setUp(self):
        user = get_user_model()
        self.admin = user.objects.create_user(username='analytics-admin', role='admin')
        self.student = user.objects.create_user(username='analytics-student', role='student')
        self.other = user.objects.create_user(username='analytics-member', role='student')
        self.year = SchoolYear.objects.create(label='2026-2027')
        self.sem = Semester.objects.create(school_year=self.year, label=Semester.FIRST, is_active=True)
        self.second = Semester.objects.create(school_year=self.year, label=Semester.SECOND)
        self.stage, _ = DefenseStage.objects.get_or_create(label='Concept Proposal', defaults={'display_order': 1})
        self.rubric = Rubric.objects.create(name='Concept panel', semester=self.sem, defense_stage=self.stage,
                                            evaluation_type='panel', status='published')
        self.criterion = RubricCriterion.objects.create(rubric=self.rubric, name='Problem relevance', max_score=10)
        StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.sem, panel_rubric=self.rubric)
        self.a = self.team('CloudSync')
        self.b = self.team('HarvestLink')
        self.pending = self.team('AwaitingTeam')
        self.grade_a = self.grade(self.a)
        self.grade_b = self.grade(self.b)
        # The cohort mean must be 70%, despite CloudSync having three panelists.
        for score in (5, 6, 7):
            GradeBreakdown.objects.create(team_grade=self.grade_a, rubric=self.rubric,
                                          evaluation_type='panel', criterion_name='Problem relevance',
                                          score=score, max_score=10, remarks=f'Recorded panel score {score}')
        GradeBreakdown.objects.create(team_grade=self.grade_b, rubric=self.rubric,
                                      evaluation_type='panel', criterion_name='Problem relevance', score=8, max_score=10)
        GradeBreakdown.objects.create(team_grade=self.grade_a, rubric=self.rubric,
                                      evaluation_type='panel', criterion_name='Problem relevance', score=10,
                                      max_score=10, is_void=True)
        self.client.force_authenticate(self.admin)

    def team(self, name, level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', semester=None):
        t = StudentTeam.objects.create(name=name, project_title=f'{name} project', level=level,
                                       year_level=year_level, semester=semester or self.sem, leader=self.student)
        TeamMembership.objects.create(team=t, student=self.student)
        TeamMembership.objects.create(team=t, student=self.other)
        return t

    def grade(self, team, **kwargs):
        return TeamGrade.objects.create(team=team, semester=team.semester, scope='capstone',
                                         defense_stage=self.stage, **kwargs)

    def get(self, **params):
        return self.client.get('/api/curriculum-analytics/explorer/', {'scope': 'capstone', **params})

    def test_annual_only_contains_recorded_years_and_published_scores(self):
        TeamGrade.all_objects.filter(pk=self.grade_a.pk).update(status='published', final_grade=61)
        TeamGrade.all_objects.filter(pk=self.grade_b.pk).update(status='published', final_grade=79)
        response = self.get()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['academic_years'], ['2026-2027'])
        self.assertEqual(response.data['annual_performance'][0]['score'], 70)
        self.assertEqual(response.data['annual_performance'][0]['assessed'], 2)
        self.assertEqual(response.data['annual_performance'][0]['eligible'], 3)

    def test_criteria_equal_weight_subjects_exclude_void_and_pending(self):
        response = self.get(academic_year='2026-2027')
        self.assertEqual(response.status_code, 200)
        criteria = response.data['criteria']
        self.assertEqual(len(criteria), 1)
        c = criteria[0]
        self.assertEqual(c['score'], 70)
        self.assertEqual(c['assessed'], 2)
        self.assertEqual(c['eligible'], 3)
        self.assertEqual(c['below'], 1)
        self.assertEqual([t['score'] for t in c['teams']], [60, 80, None])
        changed = self.get(academic_year='2026-2027', reference=85)
        self.assertEqual(changed.data['criteria'][0]['below'], 2)
        self.assertEqual(changed.data['criteria'][0]['score'], 70)

    def test_published_summary_is_stage_scoped_and_independent_of_rubric_scores(self):
        TeamGrade.all_objects.filter(pk=self.grade_a.pk).update(status='published', final_grade=61)
        # A saved final grade is not published evidence.
        TeamGrade.all_objects.filter(pk=self.grade_b.pk).update(final_grade=99)
        other_stage, _ = DefenseStage.objects.get_or_create(
            label='Summary Other Stage', defaults={'display_order': 5})
        other_grade = TeamGrade.objects.create(team=self.a, semester=self.sem,
            scope='capstone', defense_stage=other_stage)
        TeamGrade.all_objects.filter(pk=other_grade.pk).update(status='published', final_grade=95)
        summary = self.get(academic_year=self.year.label, semester=self.sem.pk,
                           context=f'stage:{self.stage.pk}').data['assessment_summary']
        self.assertEqual(summary['score'], 61)
        self.assertEqual(summary['assessed'], 1)
        self.assertEqual(summary['eligible'], 3)
        self.assertEqual(summary['pending'], 2)
        self.assertEqual([t['score'] for t in summary['teams']], [None, 61, None])
        # Evaluation source and analysis target never change final grade metrics.
        changed = self.get(academic_year=self.year.label, semester=self.sem.pk,
                           context=f'stage:{self.stage.pk}', evaluation_type='peer',
                           reference=85).data['assessment_summary']
        self.assertEqual(changed, summary)

    def test_published_summary_preserves_empty_and_zero_grade_states(self):
        TeamGrade.all_objects.filter(pk=self.grade_a.pk).update(status='published', final_grade=0)
        summary = self.get(academic_year=self.year.label).data['assessment_summary']
        self.assertEqual(summary['score'], 0)
        self.assertEqual(summary['assessed'], 1)
        empty = self.get(academic_year='2024-2025').data['assessment_summary']
        self.assertIsNone(empty['score'])
        self.assertEqual(empty['teams'], [])
        self.assertEqual(empty['eligible'], 0)

    def test_files_are_not_projects_and_administrative_files_are_not_evidence(self):
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='P', label='Project proposal',
                                         is_defense_material=True)
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='M', label='Defense minutes',
                                         is_restricted=True)
        text = 'CloudSync develops a responsive web application using React and Django. Its web portal connects local users to a REST API.'
        DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label, deliverable_id='P',
                                              label='Project proposal', deliverable_type='pre', file_name='proposal.pdf',
                                              extracted_text=text, category='Web Development', category_confidence=88)
        DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label, deliverable_id='M',
                                              label='Defense minutes', deliverable_type='post', file_name='minutes.pdf',
                                              extracted_text=text, category='IoT', category_confidence=99)
        response = self.get(academic_year='2026-2027')
        self.assertEqual(response.data['projects_count'], 3)
        counts = {d['category']: d['count'] for d in response.data['project_distribution']}
        self.assertEqual(counts, {'Unclassified': 2, 'Web Development': 1})
        detail = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                 {'scope': 'capstone', 'academic_year': '2026-2027'})
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(len(detail.data['documents']), 1)
        self.assertEqual(detail.data['documents'][0]['file_name'], 'proposal.pdf')
        self.assertEqual(len(detail.data['assessments'][0]['criteria'][0]['records']), 3)

    def test_empty_period_does_not_fallback_to_other_years(self):
        response = self.get(academic_year='2024-2025')
        self.assertEqual(response.data['projects_count'], 0)
        self.assertEqual(response.data['criteria'], [])
        self.assertEqual(response.data['contexts'], [])

    def test_source_documents_use_repository_current_file_and_deliverable_metadata(self):
        from repository.project_archive.payloads import capstone_entry_payload
        from repository.deliverables.services import submission_payload

        old_text = ('Objectives\nCloudSync monitors sensors, soil moisture and crop irrigation.\n'
                    'Expected Outputs\nAn IoT embedded telemetry prototype supports farmers.')
        current_text = ('Abstract\nCloudSync develops a responsive web application for patients in a hospital.\n'
                        'Methodology\nReact and Django provide browser forms for patient records.')
        parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='D1', label='Chapter 1-3', deliverable_type='pre', uploaded_by=self.student,
            file='deliverables/parent.pdf', file_name='parent.pdf', extracted_text=old_text)
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='D1',
            label='Chapter 1-3', is_defense_material=True)
        old = DeliverableSubmissionFile.objects.create(submission=parent,
            file='deliverables/old.pdf', file_name='old.pdf', extracted_text=old_text)
        latest = DeliverableSubmissionFile.objects.create(submission=parent,
            file='deliverables/current.pdf', file_name='current.pdf', extracted_text=current_text)
        # Equal timestamps must still choose the last upload deterministically.
        DeliverableSubmissionFile.objects.filter(pk=old.pk).update(uploaded_at=latest.uploaded_at)
        response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                  {'scope': 'capstone', 'academic_year': self.year.label})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['documents']), 1)
        document = response.data['documents'][0]
        repository_document = capstone_entry_payload(parent)[0]
        self.assertEqual(document['id'], f'file:{latest.pk}')
        self.assertEqual(document['file_name'], repository_document['file_name'])
        self.assertEqual(document['url'], repository_document['file_url'])
        self.assertEqual(document['file_name'], submission_payload(parent)['file_name'])
        self.assertIn('/api/media/', document['url'])
        self.assertEqual(document['display_name'], 'D1 · Chapter 1-3')
        self.assertEqual(document['stage'], self.stage.label)
        self.assertEqual(document['status'], 'Pending Review')
        self.assertEqual(document['uploaded_by'], self.student.username)
        self.assertEqual(response.data['classification']['label'], 'Web Development')
        self.assertEqual(response.data['classification']['document_id'], document['id'])
        self.assertEqual(response.data['classification']['source_label'], document['display_name'])
        profile = response.data['profile']
        self.assertEqual(profile['primary_document_id'], document['id'])
        self.assertEqual(profile['description']['document_id'], document['id'])
        self.assertEqual([p['name'] for p in profile['platforms']], ['Web'])
        self.assertNotIn('_raw_text', document)
        self.assertEqual(parent.files.count(), 2)  # History remains stored.

    def test_legacy_source_without_file_is_explicitly_unavailable(self):
        parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='P', label='Project proposal', deliverable_type='pre', file_name='missing.pdf',
            extracted_text='CloudSync develops a responsive web application using React and Django.')
        response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                  {'scope': 'capstone', 'academic_year': self.year.label})
        self.assertEqual(len(response.data['documents']), 1)
        document = response.data['documents'][0]
        self.assertEqual(document['id'], f'submission:{parent.pk}')
        self.assertEqual(document['display_name'], 'P · Project proposal')
        self.assertIsNone(document['url'])

    def test_current_post_deliverable_supersedes_archive_only_in_its_period_and_version(self):
        text = 'CloudSync develops a responsive web application using React and Django for browser registration.'
        self.a.project_version = 2
        self.a.save(update_fields=['project_version'])
        parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='D3', label='Approved Concept Paper', deliverable_type='post',
            file='deliverables/concept.pdf', file_name='concept.pdf', extracted_text=text)
        copy = ArchiveEntry.objects.create(team=self.a, entry_type='capstone', academic_year=self.year.label,
            semester_label=self.sem.label, stage_label=self.stage.label, file_name='archive-copy.pdf',
            metadata={'deliverable_label': 'Approved Concept Paper'}, extracted_text=text)
        later = ArchiveEntry.objects.create(team=self.a, entry_type='capstone', academic_year=self.year.label,
            semester_label=self.second.label, stage_label=self.stage.label, file_name='later.pdf',
            metadata={'deliverable_label': 'Approved Concept Paper'}, extracted_text=text)
        previous_year = SchoolYear.objects.create(label='2025-2026')
        Semester.objects.create(school_year=previous_year, label=Semester.FIRST)
        historical = ArchiveEntry.objects.create(team=self.a, entry_type='capstone',
            academic_year=previous_year.label, semester_label=self.sem.label, stage_label=self.stage.label,
            file_name='historical.pdf', metadata={'deliverable_label': 'Approved Concept Paper'}, extracted_text=text)
        # Uploads inherit the team's current version; restore a historical
        # snapshot explicitly in the isolated test database.
        ArchiveEntry.objects.filter(pk=historical.pk).update(project_version=1)
        current = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:2/',
            {'scope': 'capstone', 'academic_year': self.year.label, 'semester': self.sem.pk})
        self.assertEqual([d['id'] for d in current.data['documents']], [f'submission:{parent.pk}'])
        other_period = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:2/',
            {'scope': 'capstone', 'academic_year': self.year.label, 'semester': self.second.pk})
        self.assertEqual([d['id'] for d in other_period.data['documents']], [f'archive:{later.pk}'])
        other_version = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
            {'scope': 'capstone', 'academic_year': previous_year.label})
        self.assertEqual([d['id'] for d in other_version.data['documents']], [f'archive:{historical.pk}'])
        self.assertTrue(ArchiveEntry.objects.filter(pk=copy.pk).exists())

    def test_distinct_deliverables_keep_their_metadata_even_with_identical_text(self):
        text = 'CloudSync develops a responsive web application using React and Django for browser registration.'
        for deliverable_id, label, kind in [('D2', 'Concept Paper', 'pre'), ('D3', 'Approved Concept Paper', 'post')]:
            DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
                deliverable_id=deliverable_id, label=label, deliverable_type=kind, extracted_text=text)
        response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                  {'scope': 'capstone', 'academic_year': self.year.label})
        self.assertEqual({d['display_name'] for d in response.data['documents']},
                         {'D2 · Concept Paper', 'D3 · Approved Concept Paper'})
        self.assertEqual(response.data['classification']['document_count'], 2)
        self.assertEqual(response.data['classification']['unique_documents'], 1)

    def test_pit_source_documents_also_use_only_the_latest_revision(self):
        from defense.scheduler.models import PitEventDeliverable
        team = self.team('PIT-source', StudentTeam.LEVEL_1_PIT, '1st Year')
        event = PitEventGradingConfig.objects.create(semester=self.sem, event_name='Programming Expo')
        PitEventDeliverable.objects.create(pit_event_config=event, deliverable_id='D1',
            label='Project documentation', is_defense_material=True)
        parent = DeliverableSubmission.objects.create(team=team, stage_label=event.event_name,
            deliverable_id='D1', label='Project documentation', deliverable_type='pre')
        old = DeliverableSubmissionFile.objects.create(submission=parent, file_name='old.pdf')
        latest = DeliverableSubmissionFile.objects.create(submission=parent, file_name='latest.pdf')
        DeliverableSubmissionFile.objects.filter(pk=old.pk).update(uploaded_at=latest.uploaded_at - timedelta(days=1))
        response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{team.pk}:1/',
            {'scope': 'pit', 'year_level': '1', 'academic_year': self.year.label})
        self.assertEqual([d['id'] for d in response.data['documents']], [f'file:{latest.pk}'])
        self.assertEqual(response.data['documents'][0]['display_name'], 'D1 · Project documentation')

    def test_archive_copy_of_the_same_current_file_is_not_an_extra_source(self):
        text = 'CloudSync develops a responsive web application using React and Django for browser registration.'
        parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='P', label='Project proposal', deliverable_type='pre', extracted_text=text,
            file='deliverables/shared.pdf', file_name='shared.pdf')
        ArchiveEntry.objects.create(team=self.a, entry_type='capstone', academic_year=self.year.label,
            semester_label=self.sem.label, file='deliverables/shared.pdf', file_name='shared-archive.pdf',
            metadata={'deliverable_label': 'Project proposal'}, extracted_text=text)
        response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                  {'scope': 'capstone', 'academic_year': self.year.label})
        self.assertEqual([d['id'] for d in response.data['documents']], [f'submission:{parent.pk}'])

    def test_source_pdf_url_streams_the_current_file_with_authentication(self):
        from reportlab.pdfgen import canvas
        pdf = BytesIO()
        document = canvas.Canvas(pdf)
        document.drawString(72, 720, 'CloudSync project proposal')
        document.save()
        pdf_bytes = pdf.getvalue()
        with tempfile.TemporaryDirectory() as media, override_settings(MEDIA_ROOT=media):
            parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
                deliverable_id='P', label='Project proposal', deliverable_type='pre')
            latest = DeliverableSubmissionFile.objects.create(submission=parent,
                file=ContentFile(pdf_bytes, name='current-proposal.pdf'), file_name='current-proposal.pdf',
                extracted_text='CloudSync develops a responsive web application using React and Django.')
            response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                      {'scope': 'capstone', 'academic_year': self.year.label})
            source = response.data['documents'][0]
            self.assertEqual(source['id'], f'file:{latest.pk}')
            opened = self.client.get(source['url'])
            self.assertEqual(opened.status_code, 200)
            self.assertEqual(opened['Content-Type'], 'application/pdf')
            self.assertEqual(b''.join(opened.streaming_content), pdf_bytes)
            # The test client's streaming iterator closes the response while
            # shielding the transaction from connection cleanup signals.
            self.assertTrue(opened.closed)
            self.assertEqual(APIClient().get(source['url']).status_code, 401)

    def test_pit_is_event_and_year_level_scoped(self):
        first = self.team('PIT-first', StudentTeam.LEVEL_1_PIT, '1st Year')
        self.team('PIT-second', StudentTeam.LEVEL_2_PIT, '2nd Year')
        pit_rubric = Rubric.objects.create(name='PIT code rubric', scope='pit', semester=self.sem,
                                            evaluation_type='panel', status='published')
        RubricCriterion.objects.create(rubric=pit_rubric, name='Code fundamentals')
        event = PitEventGradingConfig.objects.create(semester=self.sem, event_name='Programming Expo',
                                                      panel_rubric=pit_rubric)
        PitEventGradingConfig.objects.create(semester=self.second, event_name='End of year showcase')
        TeamGrade.objects.create(team=first, semester=self.sem, scope='pit', pit_event_config=event,
                                  panel_weight=80, peer_weight=20)
        response = self.get(scope='pit', year_level='1', academic_year='2026-2027', semester=self.sem.pk)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['projects_count'], 1)
        self.assertEqual([c['label'] for c in response.data['contexts']], ['Programming Expo'])
        self.assertEqual([c['name'] for c in response.data['criteria']], ['Code fundamentals'])
        self.assertNotIn('adviser', [r['id'] for r in response.data['roles']])
        self.assertEqual(response.data['assessment_summary']['eligible'], 1)
        self.assertIsNone(response.data['assessment_summary']['score'])
        # An event in one semester must not count the other semester's cohort.
        self.team('PIT-first-next-semester', StudentTeam.LEVEL_1_PIT,
                  '1st Year', semester=self.second)
        across_semesters = self.get(scope='pit', year_level='1', academic_year=self.year.label,
                                    context=f'event:{event.pk}')
        self.assertEqual(across_semesters.data['projects_count'], 2)
        self.assertEqual(across_semesters.data['assessment_summary']['eligible'], 1)
        self.assertEqual(self.get(scope='pit', year_level='1', evaluation_type='adviser').status_code, 400)
        forbidden = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                    {'scope': 'pit', 'year_level': '1'})
        self.assertEqual(forbidden.status_code, 404)

    def test_peer_subjects_remain_individual(self):
        peer = Rubric.objects.create(name='Peer contributions', semester=self.sem, defense_stage=self.stage,
                                     evaluation_type='peer', status='published')
        RubricCriterion.objects.create(rubric=peer, name='Work contribution', max_score=5)
        StageGradingConfig.objects.filter(defense_stage=self.stage, semester=self.sem).update(peer_rubric=peer)
        for student, points in ((self.student, 2), (self.other, 4)):
            GradeBreakdown.objects.create(team_grade=self.grade_a, rubric=peer, student=student,
                                          evaluation_type='peer', criterion_name='Work contribution',
                                          score=points, max_score=5)
        c = self.get(academic_year='2026-2027', evaluation_type='peer').data['criteria'][0]
        self.assertEqual(c['target_type'], 'individual')
        self.assertEqual(c['score'], 60)
        self.assertEqual(c['assessed'], 2)
        self.assertEqual(c['eligible'], 6)
        self.assertEqual(c['teams'][0]['assessed'], 2)

    def test_actual_peer_submission_json_is_used_with_student_and_evaluator_evidence(self):
        peer = Rubric.objects.create(name='Peer live rubric', semester=self.sem, defense_stage=self.stage,
                                     evaluation_type='peer', status='published')
        RubricCriterion.objects.create(rubric=peer, name='Teamwork', max_score=5)
        StageGradingConfig.objects.filter(defense_stage=self.stage, semester=self.sem).update(peer_rubric=peer)
        PeerEvaluationSubmission.objects.create(team_grade=self.grade_a, evaluator=self.student, evaluatee=self.other,
            total_score=4, max_score=5, breakdown=[{'criteriaName': 'Teamwork', 'score': 4, 'max': 5}])
        response = self.get(academic_year='2026-2027', evaluation_type='peer')
        self.assertEqual(len(response.data['criteria']), 1)
        c = response.data['criteria'][0]
        self.assertEqual(c['score'], 80)
        self.assertEqual(c['assessed'], 1)
        self.assertEqual(c['eligible'], 6)
        detail = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
            {'scope': 'capstone', 'academic_year': '2026-2027'})
        evidence = next(c for c in detail.data['assessments'][0]['criteria'] if c['evaluation_type'] == 'peer')
        self.assertEqual(evidence['student_name'], self.other.username)
        self.assertEqual(evidence['records'][0]['evaluator'], self.student.username)

    def test_admin_permission_and_invalid_scopes(self):
        self.assertEqual(self.get(scope='all').status_code, 400)
        self.assertEqual(self.get(academic_year='2025-2026', semester=self.sem.pk).status_code, 400)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.get().status_code, 403)

    def test_meeting_export_uses_same_recorded_scope_and_reference(self):
        for fmt in ('json', 'csv', 'xlsx', 'pdf'):
            response = self.client.get('/api/curriculum-analytics/explorer/report/',
                                       {'scope': 'capstone', 'academic_year': '2026-2027',
                                        'reference': 85, 'export_format': fmt})
            self.assertEqual(response.status_code, 200, fmt)
            if fmt == 'json':
                self.assertEqual(response.data['rows'][0]['score'], '70.0%')
                self.assertEqual(response.data['rows'][0]['below'], '2')
                self.assertIn('85.0%', str(response.data['metadata']))
            elif fmt == 'pdf':
                self.assertTrue(response.content.startswith(b'%PDF'))

    def test_replaced_and_removed_files_invalidate_old_ml_results(self):
        submission = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='REPLACE', label='Project proposal', deliverable_type='pre', file='old.pdf',
            extracted_text='Old web project description', topics=['web'], summary='Old summary',
            category='Web Development', category_confidence=90)
        submission.file = 'new.pdf'
        extracted = {'text': 'New sensor monitoring project description', 'topics': ['sensor'],
                     'summary': 'New summary', 'category': 'IoT', 'classification': {'confidence_score': 82}}
        with patch('django.db.models.fields.files.FieldFile.open', return_value=MagicMock()), \
             patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object', return_value=extracted) as processor:
            submission.save(update_fields=['file'])
            processor.assert_called_once()
        submission.refresh_from_db()
        self.assertEqual(submission.category, 'IoT')
        self.assertEqual(submission.extracted_text, extracted['text'])
        submission.file = ''
        submission.save(update_fields=['file'])
        submission.refresh_from_db()
        self.assertEqual(submission.extracted_text, '')
        self.assertEqual(submission.topics, [])
        self.assertIsNone(submission.category_confidence)

    def test_project_detail_includes_all_assessments_when_requested(self):
        second_stage, _ = DefenseStage.objects.get_or_create(label='Explorer Final', defaults={'display_order': 5})
        TeamGrade.objects.create(team=self.a, semester=self.sem, scope='capstone', defense_stage=second_stage)
        response = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
            {'scope': 'capstone', 'academic_year': '2026-2027', 'all_assessments': 'true'})
        self.assertEqual(len(response.data['assessments']), 2)

    def test_matched_primary_pit_archive_supports_localhost_projects_without_new_profile(self):
        team = self.team('PIT-local-app', StudentTeam.LEVEL_1_PIT, '1st Year')
        team.project_title = 'Local library system'
        team.save(update_fields=['project_title'])
        ArchiveEntry.objects.create(team=team, entry_type='pit', academic_year=self.year.label,
            semester_label=self.sem.label, year_level='1st Year',
            file_name='1stYear.PIT101.LocalLibrary.1stSemester.pdf',
            metadata={'matched': True, 'project_title': 'Local library system'},
            extracted_text='A responsive web application runs on localhost for library inventory. The React frontend and Django web portal connect to a local database.',
            category='Web Development', category_confidence=88)
        ArchiveEntry.objects.create(team=team, entry_type='pit', academic_year=self.year.label,
            semester_label=self.sem.label, year_level='1st Year',
            file_name='1stYear.PIT101.LocalLibrary_MinutesOfMeeting.1stSemester.pdf',
            metadata={'matched': True, 'project_title': 'Local library system'},
            extracted_text='A misleading high scoring administrative attachment about sensors and Arduino.',
            category='IoT', category_confidence=99)
        response = self.get(scope='pit', year_level='1', academic_year=self.year.label)
        self.assertEqual(response.data['projects_count'], 1)
        self.assertEqual(response.data['project_distribution'][0]['category'], 'Web Development')

    def test_legacy_criteria_do_not_merge_different_semesters(self):
        later = TeamGrade.objects.create(team=self.a, semester=self.second, scope='capstone', defense_stage=self.stage)
        for grade, score in ((self.grade_a, 5), (later, 9)):
            GradeBreakdown.objects.create(team_grade=grade, evaluation_type='panel', criterion_name='Legacy criterion',
                                          score=score, max_score=10)
        response = self.get(academic_year=self.year.label)
        legacy = [c for c in response.data['criteria'] if c['name'] == 'Legacy criterion']
        self.assertEqual(len(legacy), 2)
        self.assertEqual({c['semester_label'] for c in legacy}, {Semester.FIRST, Semester.SECOND})
        self.assertEqual(sorted(c['score'] for c in legacy), [50, 90])

    def test_project_analytics_count_projects_and_explain_current_estimates(self):
        text = ('Abstract\nCloudSync develops a responsive web application for patients in a hospital.\n'
                'Methodology\nThe React frontend and Django web portal provide browser forms for patient records.')
        parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='ANALYTICS', label='Project proposal', deliverable_type='pre',
            extracted_text=text, category='Other', category_confidence=20)
        DeliverableSubmissionFile.objects.create(submission=parent, file_name='copy.pdf', extracted_text=text)
        DeliverableSubmission.objects.create(team=self.b, stage_label=self.stage.label,
            deliverable_id='ANALYTICS', label='Project proposal', deliverable_type='pre',
            extracted_text='Objectives\nThe agricultural project collects soil moisture and sensor measurements for crop monitoring.\nExpected Outputs\nAn IoT embedded telemetry prototype supports farmers with sensor data and irrigation alerts.')
        response = self.get(academic_year=self.year.label)
        analytics = response.data['project_analytics']
        self.assertEqual(analytics['coverage']['classified'], 2)
        self.assertEqual(analytics['coverage']['unresolved'], 1)
        react = next(t for t in analytics['technologies'] if t['category'] == 'React')
        self.assertEqual(react['count'], 1)
        groups = {g['category']: g for g in analytics['performance'][0]['categories']}
        self.assertEqual(groups['Web Development']['score'], 60)
        self.assertEqual(groups['IoT']['score'], 80)
        self.assertEqual(groups['Web Development']['assessed_teams'], 1)
        detail = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                {'scope': 'capstone', 'academic_year': self.year.label})
        self.assertEqual(detail.data['classification']['domain'], 'Healthcare')
        self.assertEqual(detail.data['classification']['unique_documents'], 1)
        self.assertTrue(detail.data['classification']['evidence'])
        self.assertNotIn('_text', detail.data['documents'][0])
        parent.refresh_from_db()
        self.assertEqual(parent.category, 'Other')  # GET remains read-only.

    def test_unrelated_uploaded_text_has_a_specific_reason(self):
        self.a.project_title = 'Smart Agriculture Crop Soil Monitoring'
        self.a.save(update_fields=['project_title'])
        DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='WRONG', label='Project proposal', deliverable_type='pre',
            extracted_text='We configure network topology, routing and switching. The network monitoring platform reports bandwidth across routers and switches.')
        project = next(p for p in self.get(academic_year=self.year.label).data['projects'] if p['team_id'] == self.a.pk)
        self.assertEqual(project['classification_reason_code'], 'unrelated_documents')
        detail = self.client.get(f'/api/curriculum-analytics/explorer/projects/{self.a.pk}:1/',
                                 {'scope': 'capstone', 'academic_year': self.year.label})
        self.assertEqual(detail.data['profile']['source_count'], 0)
        self.assertNotIn('features', detail.data['profile'])
        self.assertIsNone(detail.data['profile']['description'])

    def test_reclassification_changes_only_derived_fields_and_creates_backup(self):
        parent = DeliverableSubmission.objects.create(team=self.a, stage_label=self.stage.label,
            deliverable_id='REFRESH', label='Project proposal', deliverable_type='pre', status='accepted',
            file_name='unchanged.pdf', feedback='Keep this review.',
            extracted_text='The responsive web application uses a React frontend and Django web portal for browser registration.',
            category='Other', category_confidence=20)
        original_uploaded_at = parent.uploaded_at
        grade_before = self.grade_a.final_grade
        with tempfile.TemporaryDirectory() as temporary:
            backup = Path(temporary) / 'classification-backup.json'
            call_command('reclassify_project_documents', scope='capstone', academic_year=self.year.label,
                         apply=True, backup=str(backup), stdout=StringIO())
            self.assertTrue(backup.is_file())
        parent.refresh_from_db()
        self.assertEqual(parent.category, 'Web Development')
        self.assertTrue(parent.classification['evidence'])
        self.assertEqual(parent.status, 'accepted')
        self.assertEqual(parent.file_name, 'unchanged.pdf')
        self.assertEqual(parent.feedback, 'Keep this review.')
        self.assertEqual(parent.uploaded_at, original_uploaded_at)
        self.grade_a.refresh_from_db()
        self.assertEqual(self.grade_a.final_grade, grade_before)
