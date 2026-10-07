"""Read-only, source-backed curriculum drilldown.

Projects are team records, not files. Each period keeps the team's latest
project version. Grades come from recorded assessments; document ML is only
used for estimated computing categories. Nothing here creates or updates data.
"""
from collections import Counter, defaultdict
from statistics import mean
from types import SimpleNamespace
from decimal import Decimal
import math
import re

from django.conf import settings
from django.db.models import Prefetch
from rest_framework.exceptions import NotFound, ValidationError

from academic_period_management.models import Semester
from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from grading.grades.models import GradeBreakdown, TeamGrade, PeerEvaluationSubmission
from grading.rubrics.models import Rubric
from repository.archive.models import ArchiveEntry
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import StudentTeam
from user_management.academic_records.models import StudentAcademicRecord
from .services import ensure_admin
from repository.deliverables.project_classification import classification_for_document
from repository.deliverables.classification_taxonomy import MODEL_VERSION


ROLES = {'panel': 'Panel', 'adviser': 'Adviser', 'peer': 'Peer'}
YEAR_LEVELS = {'1': '1st Year', '2': '2nd Year', '3': '3rd Year'}
UNCLASSIFIED = 'Unclassified'
# This is an abstention setting, not a model accuracy claim or a passing grade.
MIN_MODEL_SCORE = 60
ADMIN_DOCUMENT = re.compile(
    r'\b(minutes|attendance (sheet|form)|rubric|evaluation form|approval form|'
    r'clearance|consent|endorsement|transmittal|appointment|certificate|receipt|checklist)\b', re.I,
)
PROJECT_DOCUMENT = re.compile(
    r'\b(project|proposal|concept paper|manuscript|thesis|research|technical|'
    r'executive journal|final paper|source code|documentation|abstract)\b', re.I,
)


def _name(user):
    if not user:
        return ''
    return user.get_full_name().strip() or user.username


def _average(values):
    values = [float(value) for value in values if value is not None]
    return round(mean(values), 2) if values else None


def _float(value):
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def _context_key(grade):
    if grade.scope == 'pit' and grade.pit_event_config_id:
        return f'event:{grade.pit_event_config_id}'
    if grade.scope == 'capstone' and grade.defense_stage_id:
        return f'stage:{grade.defense_stage_id}'
    return f'legacy:{grade.stage_label.strip().casefold()}'


def _is_project_document(label, config=None):
    # A restricted administrative attachment cannot become ML evidence merely
    # because its filename or text contains the team's project title.
    if config and config.is_restricted:
        return False
    label = (config.label if config else label) or ''
    label = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', label).replace('_', ' ')
    if ADMIN_DOCUMENT.search(label):
        return False
    return bool((config and config.is_defense_material) or PROJECT_DOCUMENT.search(label))


def _document(obj, label, source):
    topics = obj.topics if isinstance(obj.topics, list) else []
    text = re.sub(r'\s+', ' ', obj.extracted_text or '').strip()
    classification = classification_for_document(obj.extracted_text or '', getattr(obj, 'classification', {}))
    try:
        url = obj.file.url if obj.file else None
    except (ValueError, AttributeError):
        url = None
    return {
        'id': f'{source}:{obj.pk}', 'file_name': obj.file_name, 'label': label,
        'url': url, 'category': obj.category or '',
        'model_score': _float(obj.category_confidence), 'topics': [str(t) for t in topics[:10]],
        'excerpt': text[:1000], 'readable': len(text) >= 40,
        'classification': classification, '_text': text,
        'uploaded_at': obj.uploaded_at.isoformat(),
    }


class CurriculumExplorer:
    def __init__(self, user, params):
        ensure_admin(user)
        self.scope = params.get('scope') or 'capstone'
        if self.scope not in ('capstone', 'pit'):
            raise ValidationError({'scope': 'Select Capstone or PIT separately.'})
        self.year_level = str(params.get('year_level') or '1') if self.scope == 'pit' else None
        if self.scope == 'pit' and self.year_level not in YEAR_LEVELS:
            raise ValidationError({'year_level': 'Select 1st, 2nd or 3rd Year PIT.'})
        self.year = params.get('academic_year') or None
        self.all_assessments = params.get('all_assessments') == 'true'
        self.semester_id = str(params.get('semester') or '') or None
        self.role = params.get('evaluation_type') or 'panel'
        self.roles = {k: v for k, v in ROLES.items() if self.scope == 'capstone' or k != 'adviser'}
        if self.role not in self.roles:
            raise ValidationError({'evaluation_type': 'Evaluation source is not available in this workflow.'})
        self.reference = _float(params.get('reference', 75))
        if self.reference is None or not 0 <= self.reference <= 100:
            raise ValidationError({'reference': 'Use an analysis reference from 0 to 100.'})
        self.semesters = {str(s.pk): s for s in Semester.objects.select_related('school_year')}
        if self.semester_id:
            semester = self.semesters.get(self.semester_id)
            if not semester or not self.year or semester.school_year.label != self.year:
                raise ValidationError({'semester': 'Semester must belong to the selected academic year.'})
        self.teams = {t.pk: t for t in StudentTeam.objects.select_related(
            'semester__school_year', 'leader',
        ).prefetch_related('memberships__student')}
        self.academic_levels = {(r.student_id, r.semester_id): r.year_level
                               for r in StudentAcademicRecord.objects.all()}
        self.grades = list(TeamGrade.all_objects.filter(scope=self.scope).select_related(
            'team', 'semester__school_year', 'defense_stage', 'pit_event_config', 'schedule__rubric',
        ).prefetch_related(
            Prefetch('breakdowns', queryset=GradeBreakdown.objects.filter(is_void=False).select_related(
                'rubric', 'student', 'source_submission__panelist', 'source_submission__schedule',
            ).order_by('id')),
            'student_grades__student',
            Prefetch('peer_evaluation_submissions', queryset=PeerEvaluationSubmission.objects.select_related('evaluator', 'evaluatee')),
        ))
        self._peer_cache = {}
        self._classification_cache = {}
        self._rubric_objects = {r.pk: r for r in Rubric.objects.filter(scope=self.scope)}
        self._historical_configs = {(f'stage:{c.defense_stage_id}', c.semester_id): c for c in StageGradingConfig.objects.all()}
        self.grades = [g for g in self.grades if self._grade_in_level(g)]
        self.projects = {}
        for team in self.teams.values():
            if self._team_in_scope(team):
                self._add_project(team, team.project_version, team.semester, team.project_title)
        for grade in self.grades:
            self._add_project(self.teams[grade.team_id], grade.project_version, grade.semester,
                              grade.project_title_snapshot)['grades'].append(grade)
        self._load_documents()
        self.selected = self._selected_projects()
        self.contexts, self.context_configs = self._contexts()
        context_id = params.get('context') or None
        if context_id and context_id not in {c['id'] for c in self.contexts}:
            raise ValidationError({'context': 'Stage or event does not belong to the selected period.'})
        self.context_id = context_id or (self.contexts[0]['id'] if self.contexts else None)
        self.criteria = self._criteria() if self.year and self.context_id else []

    def _team_in_scope(self, team):
        return (team.is_capstone if self.scope == 'capstone' else
                team.is_pit and team.year_level == YEAR_LEVELS[self.year_level])

    def _grade_in_level(self, grade):
        if self.scope == 'capstone':
            return True  # Grade.scope is the historical workflow snapshot.
        team = self.teams[grade.team_id]
        level = self.academic_levels.get((team.leader_id, grade.semester_id))
        if level is None and team.semester_id == grade.semester_id and team.is_pit:
            level = team.year_level
        # Never guess a historical year level from today's promoted team.
        return level == YEAR_LEVELS[self.year_level]

    def _add_project(self, team, version, semester, title=''):
        key = (team.pk, version)
        if key not in self.projects:
            self.projects[key] = {'key': f'{team.pk}:{version}', 'team': team, 'version': version,
                                  'title': title or team.project_title, 'periods': set(),
                                  'grades': [], 'documents': []}
        project = self.projects[key]
        project['periods'].add(str(semester.pk))
        if title:
            # Current project names can be corrected after an earlier assessment
            # snapshot. A stale grade title must not make its current documents
            # look unrelated; historical project versions keep their snapshots.
            project['title'] = team.project_title or title if version == team.project_version else title
        return project

    def _load_documents(self):
        if not self.projects:
            return
        cap_configs = {(c.defense_stage.label.casefold(), c.deliverable_id): c for c in
                       StageDeliverable.objects.select_related('defense_stage')}
        pit_configs = {(c.pit_event_config.event_name.casefold(), c.deliverable_id): c for c in
                       PitEventDeliverable.objects.select_related('pit_event_config')}
        configs = cap_configs if self.scope == 'capstone' else pit_configs
        context_labels = {g.stage_label.casefold() for g in self.grades}
        context_labels.update(label for label, _ in configs)
        for submission in DeliverableSubmission.all_objects.filter(
            team_id__in={p['team'].pk for p in self.projects.values()},
        ).prefetch_related('files'):
            project = self.projects.get((submission.team_id, submission.project_version))
            if not project:
                continue
            if submission.stage_label.casefold() not in context_labels:
                continue
            config = configs.get((submission.stage_label.casefold(), submission.deliverable_id))
            if not _is_project_document(submission.label, config):
                continue
            # A live deliverable has no semester FK. It can only be assigned to
            # its existing project, never used to manufacture a past cohort.
            period_ids = [str(project['team'].semester_id)] if project['version'] == project['team'].project_version else [
                str(g.semester_id) for g in project['grades'] if g.stage_label.casefold() == submission.stage_label.casefold()]
            doc = _document(submission, submission.label, 'submission')
            doc['period_ids'] = period_ids
            project['documents'].append(doc)
            for f in submission.files.all():
                doc = _document(f, submission.label, 'file')
                doc['period_ids'] = period_ids
                project['documents'].append(doc)
        for entry in ArchiveEntry.objects.filter(entry_type=self.scope, team__isnull=False).select_related('team'):
            team = self.teams.get(entry.team_id)
            if not team:
                continue
            if self.scope == 'pit' and entry.year_level != YEAR_LEVELS[self.year_level]:
                continue
            metadata = entry.metadata if isinstance(entry.metadata, dict) else {}
            label = metadata.get('deliverable_label') or metadata.get('label') or entry.file_name
            normalized = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', label).replace('_', ' ')
            primary_archive = metadata.get('matched') and metadata.get('project_title') and not ADMIN_DOCUMENT.search(normalized)
            if metadata.get('is_restricted') or not (_is_project_document(label) or primary_archive):
                continue
            semester = next((s for s in self.semesters.values() if s.school_year.label == entry.academic_year
                             and s.label.casefold() == entry.semester_label.casefold()), None)
            project = self.projects.get((entry.team_id, entry.project_version))
            if not project:
                # Only a linked, dated project record may add a historical team.
                if not semester:
                    continue
                title = entry.metadata.get('project_title', '') if isinstance(entry.metadata, dict) else ''
                project = self._add_project(team, entry.project_version, semester, title)
            elif semester:
                project['periods'].add(str(semester.pk))
            doc = _document(entry, label, 'archive')
            doc['_source_title'] = metadata.get('project_title', '') if metadata.get('matched') else ''
            doc['period_ids'] = [str(semester.pk)] if semester else []
            project['documents'].append(doc)

    def _selected_projects(self, year=None, semester_id=None):
        year = self.year if year is None else year
        semester_id = self.semester_id if semester_id is None else semester_id
        latest = {}
        for project in self.projects.values():
            periods = {p for p in project['periods'] if p in self.semesters and
                       (not year or self.semesters[p].school_year.label == year) and
                       (not semester_id or p == semester_id)}
            if not periods:
                continue
            team_id = project['team'].pk
            if team_id not in latest or project['version'] > latest[team_id]['version']:
                latest[team_id] = project
        return sorted(latest.values(), key=lambda p: (p['team'].name.casefold(), p['team'].pk))

    def _in_period(self, grade):
        return (not self.year or grade.semester.school_year.label == self.year) and (
            not self.semester_id or str(grade.semester_id) == self.semester_id)

    def _context_grades(self, project):
        return [g for g in project['grades'] if self._in_period(g) and _context_key(g) == self.context_id]

    def _contexts(self):
        if not self.year:
            return [], {}
        semester_ids = [s.pk for s in self.semesters.values() if s.school_year.label == self.year
                        and (not self.semester_id or str(s.pk) == self.semester_id)]
        contexts, configs = {}, {}
        if self.scope == 'capstone':
            for config in StageGradingConfig.objects.filter(semester_id__in=semester_ids).select_related('defense_stage'):
                stage = config.defense_stage
                key = f'stage:{stage.pk}'
                contexts[key] = {'id': key, 'label': stage.label, 'order': stage.display_order}
                configs[(key, config.semester_id)] = config
            for stage in DefenseStage.objects.filter(rubrics__semester_id__in=semester_ids,
                                                     rubrics__scope='capstone').distinct():
                key = f'stage:{stage.pk}'
                contexts.setdefault(key, {'id': key, 'label': stage.label, 'order': stage.display_order})
        else:
            for config in PitEventGradingConfig.objects.filter(semester_id__in=semester_ids).select_related('semester'):
                key = f'event:{config.pk}'
                contexts[key] = {'id': key, 'label': config.event_name, 'order': config.pk,
                                 'semester_id': str(config.semester_id), 'semester_label': config.semester.label}
                configs[(key, config.semester_id)] = config
        for project in self.selected:
            for grade in project['grades']:
                if self._in_period(grade):
                    key = _context_key(grade)
                    contexts.setdefault(key, {'id': key, 'label': grade.stage_label,
                                             'order': grade.defense_stage.display_order if grade.defense_stage else grade.pk})
        return sorted(contexts.values(), key=lambda c: (c['order'], c['label'])), configs

    def _valid_rows(self, grade):
        peers = self._peer_rows(grade)
        peer_keys = {(r.criterion_name, r.student_id) for r in peers}
        rows = [r for r in grade.breakdowns.all() if r.max_score > 0 and 0 <= r.score <= r.max_score
                and (not r.rubric_id or r.rubric.scope == self.scope)
                and (not r.source_submission_id or (not r.source_submission.is_void and
                     r.source_submission.schedule_id == grade.schedule_id))
                and not (r.evaluation_type == 'peer' and peers and
                         (r.student_id is None or (r.criterion_name, r.student_id) in peer_keys))]
        return rows + peers

    def _peer_rows(self, grade):
        if grade.pk in self._peer_cache:
            return self._peer_cache[grade.pk]
        rubric_id = self._assigned_rubric(grade, 'peer')
        rubric = self._rubric_objects.get(rubric_id)
        rows = []
        for submission in grade.peer_evaluation_submissions.all():
            if not isinstance(submission.breakdown, list):
                continue
            for index, item in enumerate(submission.breakdown):
                if not isinstance(item, dict):
                    continue
                name = item.get('criteriaName') or item.get('name') or item.get('criterion_name')
                score = _float(item.get('score'))
                maximum = _float(item.get('max', item.get('maxScore', item.get('max_score'))))
                if not name or score is None or maximum is None or maximum <= 0 or not 0 <= score <= maximum:
                    continue
                rows.append(SimpleNamespace(pk=f'peer:{submission.pk}:{index}', evaluation_type='peer',
                    criterion_name=str(name), student_id=submission.evaluatee_id, student=submission.evaluatee,
                    score=Decimal(str(score)), max_score=Decimal(str(maximum)), rubric_id=rubric_id if rubric else None, rubric=rubric,
                    source_submission_id=None, remarks=item.get('remarks', '') or '',
                    evaluator_name=_name(submission.evaluator)))
        self._peer_cache[grade.pk] = rows
        return rows

    def _assigned_rubric(self, grade, role):
        config = self.context_configs.get((_context_key(grade), grade.semester_id)) or self._historical_configs.get((_context_key(grade), grade.semester_id))
        if self.scope == 'pit' and grade.pit_event_config_id:
            config = grade.pit_event_config
        if role == 'panel' and grade.schedule_id and grade.schedule.rubric_id:
            return grade.schedule.rubric_id
        return getattr(config, f'{role}_rubric_id', None)

    def _criteria(self):
        definitions, subjects, records = {}, defaultdict(lambda: defaultdict(list)), defaultdict(list)
        rubrics = list(Rubric.objects.filter(scope=self.scope, evaluation_type=self.role,
                                             semester__school_year__label=self.year).prefetch_related('criteria'))
        if self.semester_id:
            rubrics = [r for r in rubrics if str(r.semester_id) == self.semester_id]
        applicable = set()
        for (key, sem), config in self.context_configs.items():
            if key == self.context_id:
                rid = getattr(config, f'{self.role}_rubric_id', None)
                if rid:
                    applicable.add(rid)
        for project in self.selected:
            for grade in self._context_grades(project):
                if rid := self._assigned_rubric(grade, self.role):
                    applicable.add(rid)
                for row in self._valid_rows(grade):
                    if row.evaluation_type != self.role:
                        continue
                    individual = row.student_id is not None
                    key = f'{row.rubric_id or "legacy"}:{grade.semester_id}:{row.criterion_name}:{float(row.max_score):.2f}:{"individual" if individual else "team"}'
                    definitions[key] = {'id': key, 'name': row.criterion_name, 'rubric_id': row.rubric_id,
                                        'rubric_name': row.rubric.name if row.rubric_id else 'Recorded rubric',
                                        'target_type': 'individual' if individual else 'team',
                                        'max_score': float(row.max_score), 'semester_id': str(grade.semester_id)}
                    subjects[key][(project['key'], grade.pk, row.student_id)].append(float(row.score / row.max_score * 100))
                    records[key].append((project['key'], grade.pk, row))
                    if row.rubric_id:
                        applicable.add(row.rubric_id)
        # Include configured criteria with no scores, without inventing values.
        for rubric in rubrics:
            if rubric.pk not in applicable and not (self.scope == 'capstone' and self.context_id == f'stage:{rubric.defense_stage_id}'
                                                   and rubric.status == Rubric.STATUS_PUBLISHED):
                continue
            for c in rubric.criteria.all():
                key = f'{rubric.pk}:{rubric.semester_id}:{c.name}:{c.max_score:.2f}:{c.target_type}'
                definitions.setdefault(key, {'id': key, 'name': c.name, 'rubric_id': rubric.pk,
                                              'rubric_name': rubric.name, 'target_type': c.target_type,
                                              'max_score': c.max_score, 'semester_id': str(rubric.semester_id)})
        result = []
        for key, definition in definitions.items():
            per_project = defaultdict(list)
            for (project_key, grade_id, student_id), scores in subjects[key].items():
                per_project[project_key].append(mean(scores))
            target_semester = definition['semester_id']
            teams, eligible = [], 0
            for project in self.selected:
                if target_semester not in project['periods']:
                    continue
                if self.scope == 'pit' and self.context_id.startswith('event:'):
                    config = self.context_configs.get((self.context_id, int(target_semester)))
                    if not config:
                        continue
                grades = self._context_grades(project)
                assigned = [self._assigned_rubric(g, self.role) for g in grades]
                if definition['rubric_id'] and any(assigned) and definition['rubric_id'] not in assigned:
                    continue
                member_ids = {m.student_id for m in project['team'].memberships.all()}
                member_ids.update(row.student_id for pkey, _, row in records[key] if pkey == project['key'] and row.student_id)
                total = len(member_ids) if definition['target_type'] == 'individual' else 1
                eligible += total
                scores = per_project.get(project['key'], [])
                teams.append({**self._project_summary(project), 'score': _average(scores),
                              'assessed': len(scores), 'eligible': total})
            normalized = [mean(scores) for scores in subjects[key].values()]
            result.append({**definition, 'semester_label': self.semesters[target_semester].label,
                           'score': _average(normalized), 'assessed': len(normalized),
                           'eligible': eligible, 'below': sum(s < self.reference for s in normalized),
                           'teams': sorted(teams, key=lambda t: (t['score'] is None, t['score'] or 0, t['team_name']))})
        return sorted(result, key=lambda c: (c['score'] is None, c['score'] or 0, c['name'], c['rubric_name']))

    def _documents(self, project, year=None, semester_id=None):
        year = self.year if year is None else year
        semester_id = self.semester_id if semester_id is None else semester_id
        if not year and not semester_id:
            return project['documents']
        return [d for d in project['documents'] if any(p in self.semesters and
                (not year or self.semesters[p].school_year.label == year) and
                (not semester_id or p == semester_id) for p in d['period_ids'])]

    def _category(self, project, year=None, semester_id=None):
        cache_key = (project['key'], self.year if year is None else year,
                     self.semester_id if semester_id is None else semester_id)
        if cache_key in self._classification_cache:
            return self._classification_cache[cache_key]
        docs = self._documents(project, year, semester_id)
        readable = [d for d in docs if d['readable']]
        # A wrong attachment must not classify a project from unrelated content.
        tokens = {t for t in re.findall(r'[a-z]{3,}', project['title'].lower())
                  if t not in {'project', 'system', 'smart', 'powered', 'application', 'and', 'the', 'with'}}
        related = [d for d in readable if len(tokens) < 3 or
                   sum(bool(re.search(r'\b' + re.escape(t) + r'\b', d['_text'], re.I)) for t in tokens) >= 2 or
                   d.get('_source_title') and
                   sum(bool(re.search(r'\b' + re.escape(t) + r'\b', d['_text'], re.I))
                       for t in set(re.findall(r'[a-z]{3,}', d['_source_title'].lower()))
                       if t not in {'project', 'system', 'application', 'and', 'the'}) >= 2]
        # Identical parent/file/archive copies never add votes or evidence.
        unique = {d['classification']['input_hash']: d for d in related}
        related = list(unique.values())
        usable = [d for d in related if d['classification']['status'] == 'estimated' and
                  d['classification']['confidence_score'] >= getattr(settings, 'CURRICULUM_ML_MIN_SCORE', MIN_MODEL_SCORE)]
        candidates = sorted(related, key=lambda d: -d['classification']['confidence_score'])
        domain_docs = [d for d in related if d['classification']['domain'] != 'Unresolved domain']
        domain_source = max(domain_docs, key=lambda d: len(d['classification']['domain_evidence']), default=None)
        common = {'model_version': MODEL_VERSION, 'review_status': 'Estimated; not faculty-reviewed',
                  'domain': domain_source['classification']['domain'] if domain_source else 'Unresolved domain',
                  'domain_evidence': [{**hit, 'document_id': domain_source['id'], 'file_name': domain_source['file_name']}
                                      for hit in domain_source['classification']['domain_evidence']] if domain_source else [],
                  'document_count': len(docs), 'unique_documents': len(related),
                  'readable_documents': len(readable), 'technologies': [], 'secondary_categories': []}
        technologies = {}
        for document in related:
            for technology in document['classification']['technologies']:
                technologies.setdefault(technology['name'], {**technology, 'document_id': document['id'], 'file_name': document['file_name']})
        common['technologies'] = list(technologies.values())
        if not usable:
            if not docs:
                code, reason = 'no_documents', 'No eligible project documents are linked to this period and project version.'
            elif not readable:
                code, reason = 'unreadable', 'Documents are uploaded, but their extracted text is empty or too short.'
            elif not related:
                code, reason = 'unrelated_documents', 'Uploaded text does not match the recorded project topic; review the linked documents.'
            else:
                code = candidates[0]['classification']['reason_code']
                reason = candidates[0]['classification']['reason']
            result = {**common, 'label': UNCLASSIFIED, 'status': 'unresolved',
                      'reason_code': code, 'reason': reason, 'model_score': None,
                      'candidates': candidates[0]['classification']['top_3'] if candidates else [],
                      'evidence': candidates[0]['classification']['evidence'] if candidates else []}
            self._classification_cache[cache_key] = result
            return result
        # Duplicate files cannot outvote a project: use one primary document.
        primary = max(usable, key=lambda d: (bool(re.search(r'proposal|manuscript|final paper|concept', d['label'], re.I)),
                                            d['uploaded_at'], d['classification']['confidence_score']))
        prediction = primary['classification']
        result = {**common, 'label': prediction['predicted_category'],
                  'status': 'estimated', 'reason_code': 'supported', 'reason': prediction['reason'],
                  'model_score': prediction['confidence_score'], 'margin': prediction['margin'],
                  'document_id': primary['id'], 'file_name': primary['file_name'],
                  'classified_at': prediction['classified_at'], 'training_source': prediction['training_source'],
                  'evidence': [{**hit, 'document_id': primary['id'], 'file_name': primary['file_name']} for hit in prediction['evidence']],
                  'candidates': prediction['top_3'],
                  'secondary_categories': prediction['secondary_categories'],
                  'technologies': list(technologies.values()),
                  'domain': prediction['domain'] if prediction['domain'] != 'Unresolved domain' else common['domain']}
        if prediction['domain'] != 'Unresolved domain':
            result['domain_evidence'] = [{**hit, 'document_id': primary['id'], 'file_name': primary['file_name']}
                                         for hit in prediction['domain_evidence']]
        self._classification_cache[cache_key] = result
        return result

    def _project_summary(self, project):
        periods = [self.semesters[p] for p in project['periods'] if p in self.semesters and
                   (not self.year or self.semesters[p].school_year.label == self.year) and
                   (not self.semester_id or p == self.semester_id)]
        classification = self._category(project)
        return {'id': project['key'], 'team_id': project['team'].pk, 'team_name': project['team'].name,
                'project_title': project['title'], 'project_version': project['version'],
                'category': classification['label'], 'domain': classification['domain'],
                'technologies': [t['name'] for t in classification['technologies']],
                'classification_status': classification['status'],
                'classification_reason': classification['reason'],
                'classification_reason_code': classification['reason_code'],
                'periods': [{'academic_year': s.school_year.label, 'semester': s.label} for s in periods]}

    def _project_analytics(self, projects):
        total = len(projects)
        classified = sum(p['category'] != UNCLASSIFIED for p in projects)

        def distribution(values):
            return [{'category': name, 'count': count,
                     'percentage': round(count / total * 100, 2) if total else 0}
                    for name, count in Counter(values).most_common()]

        categories = distribution(p['category'] for p in projects if p['category'] != UNCLASSIFIED)
        domains = distribution(p['domain'] for p in projects)
        technologies = distribution(t for p in projects for t in set(p['technologies']))
        reasons = distribution(p['classification_reason_code'] for p in projects
                               if p['classification_status'] == 'unresolved')
        observations = [f'{classified} of {total} projects have an estimated computing focus.'] if total else []
        if categories:
            top = categories[0]
            observations.append(f"{top['category']} is the most frequent focus: {top['count']} of {total} projects ({top['percentage']:.1f}%).")
        resolved_domains = [d for d in domains if d['category'] != 'Unresolved domain']
        if resolved_domains:
            top = resolved_domains[0]
            observations.append(f"{top['category']} is the most frequent application domain: {top['count']} projects.")
        if total - classified:
            observations.append(f'{total - classified} projects remain unresolved and are included in the cohort total.')
        project_by_id = {p['id']: p for p in projects}
        performance = []
        for criterion in self.criteria:
            groups = defaultdict(list)
            for team in criterion['teams']:
                project = project_by_id.get(team['id'])
                if project and project['category'] != UNCLASSIFIED:
                    groups[project['category']].append(team['score'])
            performance.append({'id': criterion['id'], 'name': criterion['name'],
                'rubric': criterion['rubric_name'], 'semester': criterion['semester_label'],
                'target_type': criterion['target_type'],
                'categories': [{'category': category, 'score': _average(scores),
                                'assessed_teams': sum(s is not None for s in scores),
                                'eligible_teams': len(scores)} for category, scores in groups.items()]})
        return {'coverage': {'classified': classified, 'unresolved': total - classified,
                            'domains_resolved': sum(p['domain'] != 'Unresolved domain' for p in projects),
                            'with_technologies': sum(bool(p['technologies']) for p in projects)},
                'categories': categories, 'domains': domains, 'technologies': technologies,
                'unresolved_reasons': reasons, 'observations': observations,
                'performance': performance, 'model_version': MODEL_VERSION,
                'status': 'Development model; estimates require review'}

    def _assessment_summary(self):
        """One latest published grade per team in the selected stage/event.

        Keep final grades separate from role-specific rubric results. Unpublished
        and missing grades remain pending rather than becoming zero scores.
        """
        projects = self.selected
        if self.scope == 'pit' and self.context_id:
            context = next((c for c in self.contexts if c['id'] == self.context_id), {})
            if semester_id := context.get('semester_id'):
                projects = [p for p in projects if semester_id in p['periods']]
        teams = []
        for project in projects:
            grades = self._context_grades(project) if self.context_id else []
            published = [g for g in grades if g.status == TeamGrade.STATUS_PUBLISHED
                         and _float(g.final_grade) is not None]
            latest = max(published, key=lambda g: (g.published_at or g.updated_at, g.pk)) if published else None
            teams.append({**self._project_summary(project),
                          'score': _float(latest.final_grade) if latest else None})
        scores = [t['score'] for t in teams if t['score'] is not None]
        return {'score': _average(scores), 'assessed': len(scores),
                'eligible': len(teams), 'pending': len(teams) - len(scores),
                'teams': teams}

    def payload(self):
        academic_years = sorted({self.semesters[p].school_year.label for project in self.projects.values()
                                 for p in project['periods'] if p in self.semesters})
        annual = []
        for year in academic_years:
            projects = self._selected_projects(year=year, semester_id='')
            scores = []
            for project in projects:
                published = [g for g in project['grades'] if g.semester.school_year.label == year and
                             g.status == TeamGrade.STATUS_PUBLISHED and g.final_grade is not None]
                if published:
                    latest = max(published, key=lambda g: (g.published_at or g.updated_at, g.pk))
                    scores.append(float(latest.final_grade))
            annual.append({'academic_year': year, 'score': _average(scores), 'assessed': len(scores),
                           'eligible': len(projects), 'in_progress': any(s.is_active and s.school_year.label == year
                                                                       for s in self.semesters.values())})
        projects = [self._project_summary(p) for p in self.selected]
        counts = Counter(p['category'] for p in projects)
        total = len(projects)
        trends = []
        for year in academic_years:
            match = next((str(s.pk) for s in self.semesters.values() if s.school_year.label == year and
                          self.semester_id and s.label == self.semesters[self.semester_id].label), '')
            historical = [] if self.semester_id and not match else self._selected_projects(year=year, semester_id=match)
            categories = Counter(self._category(p, year, match)['label'] for p in historical)
            domains = Counter(self._category(p, year, match)['domain'] for p in historical)
            trends.append({'academic_year': year, 'projects_count': len(historical),
                           'classified': sum(n for c, n in categories.items() if c != UNCLASSIFIED),
                           'distribution': [{'category': c, 'count': n} for c, n in categories.items()],
                           'domains': [{'category': c, 'count': n} for c, n in domains.items()]})
        return {'scope': self.scope, 'year_level': self.year_level, 'academic_year': self.year,
                'semester': self.semester_id, 'context': self.context_id, 'evaluation_type': self.role,
                'reference': self.reference, 'academic_years': academic_years, 'annual_performance': annual,
                'semesters': [{'id': str(s.pk), 'label': s.label} for s in self.semesters.values()
                              if s.school_year.label == self.year],
                'contexts': self.contexts, 'roles': [{'id': k, 'label': v} for k, v in self.roles.items()],
                'assessment_summary': self._assessment_summary(),
                'criteria': self.criteria, 'projects': projects, 'projects_count': total,
                'project_trends': trends,
                'project_analytics': self._project_analytics(projects),
                'project_distribution': [{'category': c, 'count': n, 'percentage': round(n / total * 100, 2)}
                                         for c, n in sorted(counts.items(), key=lambda x: (-x[1], x[0]))],
                'methodology': {'performance': 'Recorded rubric scores normalized to their recorded maximum. Missing scores are excluded; evaluators are consolidated per assessed subject.',
                                'annual': 'Latest published assessment per team in each academic year. In-progress years and different assessment stages are not directly comparable.',
                                'projects': 'One project per team in the selected period, using its latest project version. Uploads and assessment attempts do not add projects.',
                                'classification': 'Section-aware Naive Bayes estimates from readable project documents. References, tentative technologies and administrative attachments are excluded. Development examples are not faculty-reviewed; model scores are not measured accuracy.'}}

    def detail(self, project_id):
        project = next((p for p in self.selected if p['key'] == project_id), None)
        if not project:
            raise NotFound('Project is not in the selected workflow and period.')
        grades = self._context_grades(project) if self.context_id and self.year and not self.all_assessments else [
            g for g in project['grades'] if self._in_period(g)]
        assessments = []
        for grade in sorted(grades, key=lambda g: (g.semester.school_year.label, g.pk)):
            grouped = defaultdict(list)
            for row in self._valid_rows(grade):
                if row.evaluation_type not in self.roles:
                    continue
                key = (row.evaluation_type, row.rubric_id, row.criterion_name, float(row.max_score), row.student_id)
                source = row.source_submission if row.source_submission_id else None
                remarks = row.remarks or ''
                if source and '\n' in remarks:
                    remarks = remarks.split('\n', 1)[1].strip()
                grouped[key].append({'score': float(row.score), 'max_score': float(row.max_score),
                                     'percentage': float(row.score / row.max_score * 100),
                                     'evaluator': (_name(source.panelist) or source.guest_name) if source else getattr(row, 'evaluator_name', ROLES[row.evaluation_type]),
                                     'remarks': remarks, 'source_id': row.pk})
            criteria = []
            for (role, rid, name, maximum, student_id), rows in grouped.items():
                student = next((r.student for r in self._valid_rows(grade) if r.student_id == student_id), None) if student_id else None
                criteria.append({'evaluation_type': role, 'name': name, 'rubric_id': rid,
                                 'student_id': student_id, 'student_name': _name(student) if student else None,
                                 'max_score': maximum, 'score': _average([r['score'] for r in rows]),
                                 'percentage': _average([r['percentage'] for r in rows]), 'records': rows})
            assessments.append({'id': grade.pk, 'context': _context_key(grade), 'label': grade.stage_label,
                                'semester_id': str(grade.semester_id),
                                'academic_year': grade.semester.school_year.label, 'semester': grade.semester.label,
                                'status': grade.status, 'final_grade': _float(grade.final_grade),
                                'verdict': grade.get_verdict_display() if grade.verdict else None,
                                'remarks': grade.verdict_remarks, 'criteria': criteria})
        return {'project': self._project_summary(project), 'classification': self._category(project),
                'assessments': assessments, 'documents': [{k: v for k, v in d.items() if not k.startswith('_')} for d in self._documents(project)], 'scope': self.scope}


def explorer_payload(user, params):
    return CurriculumExplorer(user, params).payload()


def explorer_detail(user, params, project_id):
    return CurriculumExplorer(user, params).detail(project_id)
