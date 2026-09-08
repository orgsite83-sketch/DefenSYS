from collections import Counter, defaultdict
from decimal import Decimal
import re

from django.core.exceptions import PermissionDenied
from django.db.models import Avg, Q

from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import display_name
from repository.archive.models import ArchiveEntry
from grading.grades.models import TeamGrade, GradeBreakdown, PanelistCriterionScore, PeerEvaluationSubmission
from grading.rubrics.models import Rubric, RubricCriterion
from defense.stages.models import DefenseStage
from defense.scheduler.models import PitEventGradingConfig
from student_teams.models import StudentTeam
from academic_period_management.models import SchoolYear, Semester


DSS_METADATA_CATALOG = [
    {
        'key': 'cpi',
        'name': 'Competency Proficiency Index (CPI)',
        'subsystem': 'Model Management',
        'benchmark': '≥ 75.0%',
        'definition': 'The percentage of evaluated rubric criteria meeting or exceeding the 75% institutional passing threshold.',
        'decision_impact': 'Flags lower-year prerequisite courses that require syllabus or laboratory remediation.',
    },
    {
        'key': 'divergence',
        'name': 'Evaluator Discrepancy Delta (|Panel - Adviser|)',
        'subsystem': 'Knowledge-Based',
        'benchmark': '< 10.0%',
        'definition': 'The absolute average variance between external defense panelist scores and project adviser scores.',
        'decision_impact': 'Detects grading subjectivity or leniency bias, indicating when faculty rubric calibration is needed.',
    },
    {
        'key': 'friction',
        'name': 'Pipeline Bottleneck Friction Index',
        'subsystem': 'Model Management',
        'benchmark': 'Lower is better',
        'definition': 'Composite operational friction: (Redefense Rate × 2) + Revision Rate across defense stages.',
        'decision_impact': 'Reveals where student cohorts stall, prompting targeted mock defense clinics or guideline updates.',
    },
    {
        'key': 'monoculture',
        'name': 'Tech Stack Monoculture Index',
        'subsystem': 'Data Management',
        'benchmark': '< 50.0%',
        'definition': 'Percentage share of student deliverables dominated by the top software stack or framework.',
        'decision_impact': 'Prompts department leadership to introduce emerging tech thematic calls (AI, IoT, Cloud).',
    },
]

UNCLASSIFIED_TECH_STACK = 'Unclassified'
UNCLASSIFIED_DOMAIN = 'General Software & Systems'

NB_CATEGORY_TO_STACK = {
    'Web Development': 'React / Node.js',
    'Mobile Development': 'Flutter / Mobile',
    'Machine Learning': 'Django / Python',
    'Data Science': 'Django / Python',
    'Cloud Computing': 'Cloud / AWS',
    'IoT': 'IoT / Embedded',
    'Game Development': 'AR / Unity',
    'Database Systems': 'Django / Python',
    'Network Systems': 'Cloud / AWS',
    'Cybersecurity': 'Django / Python',
    'Desktop Applications': 'Django / Python',
}

NB_CATEGORY_TO_DOMAIN = {
    'Web Development': 'Web Applications & Platforms',
    'Mobile Development': 'Mobile & Ubiquitous Computing',
    'Machine Learning': 'Artificial Intelligence & ML',
    'Data Science': 'Data Analytics & BI',
    'Cloud Computing': 'Enterprise & Cloud SaaS',
    'IoT': 'IoT & Smart Hardware',
    'Game Development': 'Interactive Media & Gaming',
    'Database Systems': 'Enterprise & Cloud SaaS',
    'Network Systems': 'Cybersecurity & Network Systems',
    'Cybersecurity': 'Cybersecurity & Network Systems',
    'Desktop Applications': 'Enterprise & Cloud SaaS',
}

PROJECT_DOMAINS = [
    {
        'label': 'Artificial Intelligence & ML',
        'keywords': ['ai', 'machine learning', 'deep learning', 'neural', 'nlp', 'computer vision', 'yolo', 'detection', 'recognition', 'classifier', 'prediction', 'llm', 'transformer', 'opencv', 'chatgpt', 'artificial intelligence'],
        'color': '#8B5CF6',
        'icon': 'psychology_rounded',
        'prerequisite_course': 'IT324 Artificial Intelligence & Data Mining',
    },
    {
        'label': 'IoT & Smart Hardware',
        'keywords': ['iot', 'arduino', 'esp32', 'raspberry', 'sensor', 'embedded', 'automation', 'hardware', 'rfid', 'smart home', 'actuator', 'microcontroller', 'robotics'],
        'color': '#EC4899',
        'icon': 'memory_rounded',
        'prerequisite_course': 'IT315 Embedded Systems & IoT',
    },
    {
        'label': 'Enterprise & Cloud SaaS',
        'keywords': ['cloud', 'saas', 'erp', 'crm', 'management system', 'portal', 'inventory', 'payroll', 'billing', 'procurement', 'aws', 'docker', 'microservices', 'kubernetes', 'sync', 'storage', 'file'],
        'color': '#6366F1',
        'icon': 'cloud_sync_rounded',
        'prerequisite_course': 'IT311 Cloud Architecture & Enterprise Systems',
    },
    {
        'label': 'Mobile & Ubiquitous Computing',
        'keywords': ['mobile', 'flutter', 'react native', 'android', 'ios', 'swift', 'kotlin', 'dart', 'geolocation', 'attendance app', 'tracker app', 'mobile app'],
        'color': '#0EA5E9',
        'icon': 'phone_android_rounded',
        'prerequisite_course': 'IT222 Mobile Application Development',
    },
    {
        'label': 'GIS & Smart Community',
        'keywords': ['gis', 'map', 'mapping', 'geo', 'spatial', 'location', 'barangay', 'disaster', 'evacuation', 'land', 'cadastral'],
        'color': '#06B6D4',
        'icon': 'map_rounded',
        'prerequisite_course': 'IT322 Geographic Information Systems',
    },
    {
        'label': 'Cybersecurity & Network Systems',
        'keywords': ['security', 'cryptography', 'firewall', 'encryption', 'vulnerability', 'penetration', 'network', 'intrusion', 'audit', 'blockchain', 'auth'],
        'color': '#EF4444',
        'icon': 'shield_rounded',
        'prerequisite_course': 'IT313 Information Assurance & Security',
    },
    {
        'label': 'Data Analytics & BI',
        'keywords': ['analytics', 'dashboard', 'visualization', 'mining', 'business intelligence', 'forecasting', 'reporting', 'big data', 'grade tracker'],
        'color': '#10B981',
        'icon': 'insert_chart_rounded',
        'prerequisite_course': 'IT221 Data Analysis & Visualization',
    },
    {
        'label': 'Web Applications & Platforms',
        'keywords': ['web', 'django', 'react', 'node', 'laravel', 'vue', 'angular', 'php', 'e-commerce', 'booking', 'quiz', 'builder', 'tutor'],
        'color': '#F59E0B',
        'icon': 'language_rounded',
        'prerequisite_course': 'IT212 Web Systems & Technologies',
    },
]

TECH_STACKS = [
    {
        'label': 'Flutter / Mobile',
        'keywords': ['flutter', 'mobile', 'attendance', 'android', 'ios', 'dart', 'app'],
        'color': '#0EA5E9',
    },
    {
        'label': 'Django / Python',
        'keywords': ['django', 'python', 'web', 'portal', 'grade', 'tracker', 'dashboard', 'analytics'],
        'color': '#10B981',
    },
    {
        'label': 'React / Node.js',
        'keywords': ['react', 'node', 'javascript', 'quiz', 'lowcode', 'builder', 'peer', 'tutor', 'note'],
        'color': '#F59E0B',
    },
    {
        'label': 'Laravel / PHP',
        'keywords': ['laravel', 'php', 'social', 'network', 'campus', 'erp', 'community'],
        'color': '#EF4444',
    },
    {
        'label': 'IoT / Embedded',
        'keywords': ['iot', 'sensor', 'arduino', 'raspberry', 'embedded', 'smart', 'automation'],
        'color': '#8B5CF6',
    },
    {
        'label': 'AR / Unity',
        'keywords': ['ar', 'vr', 'unity', 'augmented', 'virtual'],
        'color': '#EC4899',
    },
    {
        'label': 'GIS / Mapping',
        'keywords': ['gis', 'map', 'geo', 'land', 'location'],
        'color': '#06B6D4',
    },
    {
        'label': 'Cloud / AWS',
        'keywords': ['cloud', 'sync', 'file', 'storage', 'aws', 'drive'],
        'color': '#6366F1',
    },
]


def ensure_admin(user):
    if getattr(user, 'role', None) != 'admin' and not getattr(user, 'is_superuser', False):
        raise PermissionDenied('Curriculum analytics is available to admins only.')


def source_entries(scope=None):
    entries = []
    include_pit = scope in [None, 'all', 'pit']
    include_capstone = scope in [None, 'all', 'capstone']

    if include_pit:
        pit_entries = ArchiveEntry.objects.select_related('team', 'uploaded_by').filter(
            entry_type=ArchiveEntry.TYPE_PIT,
        )
        for entry in pit_entries:
            entries.append({
                'id': f'pit-{entry.id}',
                'source_id': entry.id,
                'type': 'pit',
                'track': 'pit',
                'file_name': entry.file_name,
                'team_name': entry.team_name or (entry.team.name if entry.team else 'Unmatched'),
                'project_title': entry.metadata.get('project_title', '') if isinstance(entry.metadata, dict) else '',
                'deliverable_label': entry.file_name,
                'academic_year': entry.academic_year or 'Unknown',
                'year_level': entry.year_level or 'Unknown',
                'stage': entry.stage_label or entry.course_code,
                'status': entry.status,
                'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'PIT Lead',
                'uploaded_at': entry.uploaded_at,
                'extracted_text': entry.extracted_text or '',
                'topics': entry.topics or [],
                'summary': entry.summary or '',
                'category': entry.category or '',
                'category_confidence': entry.category_confidence,
            })

    if include_capstone:
        submissions = DeliverableSubmission.objects.select_related(
            'team',
            'team__semester',
            'team__semester__school_year',
            'uploaded_by',
        ).filter(team__level__icontains='Capstone')
        for submission in submissions:
            team = submission.team
            entries.append({
                'id': f'capstone-{submission.id}',
                'source_id': submission.id,
                'type': 'capstone',
                'track': 'capstone',
                'file_name': submission.file_name,
                'team_name': team.name,
                'project_title': team.project_title,
                'deliverable_id': submission.deliverable_id,
                'deliverable_label': submission.label,
                'academic_year': team.semester.school_year.label if (team.semester and team.semester.school_year) else 'Unknown',
                'year_level': team.year_level,
                'stage': submission.stage_label,
                'status': 'Post-Defense' if submission.deliverable_type == DeliverableSubmission.TYPE_POST else 'Pre-Defense',
                'uploaded_by': display_name(submission.uploaded_by) or 'System',
                'uploaded_at': submission.uploaded_at,
                'extracted_text': submission.extracted_text or '',
                'topics': submission.topics or [],
                'summary': submission.summary or '',
                'category': submission.category or '',
                'category_confidence': submission.category_confidence,
            })
    return sorted(entries, key=lambda item: item['uploaded_at'], reverse=True)



def text_for_entry(entry):
    parts = [
        entry.get('file_name'),
        entry.get('team_name'),
        entry.get('project_title'),
        entry.get('deliverable_label'),
        entry.get('stage'),
        entry.get('year_level'),
        entry.get('summary'),
        entry.get('category'),
    ]
    topics = entry.get('topics') or []
    if topics:
        parts.append(' '.join(str(topic) for topic in topics))
    extracted = (entry.get('extracted_text') or '')[:4000]
    if extracted:
        parts.append(extracted)
    return ' '.join(str(part) for part in parts if part).lower()


def keyword_matches(text, keyword):
    term = keyword.lower()
    if len(term) <= 3 and term.isalnum():
        return re.search(rf'(?<![a-z0-9]){re.escape(term)}(?![a-z0-9])', text) is not None
    return term in text


def extract_tech(entry):
    text = text_for_entry(entry)
    best = None
    best_score = 0
    for stack in TECH_STACKS:
        score = sum(1 for keyword in stack['keywords'] if keyword_matches(text, keyword))
        if score > best_score:
            best = stack
            best_score = score
    if best_score > 0 and best is not None:
        return best['label']

    if 'java' in text or 'spring' in text or 'springboot' in text:
        return 'Spring Boot / Java'
    if 'c#' in text or 'aspnet' in text or '.net' in text or 'dotnet' in text:
        return 'ASP.NET / C#'
    if 'golang' in text or 'fiber' in text or 'gin' in text or 'go lang' in text:
        return 'Go / Fiber'
    if 'rust' in text or 'cargo' in text:
        return 'Rust / Cargo'
    if 'ruby' in text or 'rails' in text:
        return 'Ruby on Rails'
    if 'c++' in text or 'cpp' in text:
        return 'C++ / Native'

    category = (entry.get('category') or '').strip()
    confidence = entry.get('category_confidence')
    if category and confidence is not None and confidence >= 15:
        mapped = NB_CATEGORY_TO_STACK.get(category)
        if mapped:
            return mapped

    return UNCLASSIFIED_TECH_STACK


def extract_domain(entry):
    text = text_for_entry(entry)
    best = None
    best_score = 0
    for dom in PROJECT_DOMAINS:
        score = sum(1 for keyword in dom['keywords'] if keyword_matches(text, keyword))
        if score > best_score:
            best = dom
            best_score = score
    if best_score > 0 and best is not None:
        return best['label']

    category = (entry.get('category') or '').strip()
    confidence = entry.get('category_confidence')
    if category and confidence is not None and confidence >= 15:
        mapped = NB_CATEGORY_TO_DOMAIN.get(category)
        if mapped:
            return mapped

    return UNCLASSIFIED_DOMAIN


def domain_color(label):
    for dom in PROJECT_DOMAINS:
        if dom['label'] == label:
            return dom['color']
    return '#64748B'


def stack_color(label):
    predefined = {
        'Flutter / Mobile': '#0EA5E9',
        'Django / Python': '#10B981',
        'React / Node.js': '#F59E0B',
        'Laravel / PHP': '#EF4444',
        'IoT / Embedded': '#8B5CF6',
        'AR / Unity': '#EC4899',
        'GIS / Mapping': '#06B6D4',
        'Cloud / AWS': '#6366F1',
        'Spring Boot / Java': '#E76F51',
        'ASP.NET / C#': '#512BD4',
        'Go / Fiber': '#00ADD8',
        'Rust / Cargo': '#DEA584',
        'Ruby on Rails': '#A259FF',
        'C++ / Native': '#00599C',
        UNCLASSIFIED_TECH_STACK: '#6B7280',
    }
    if label in predefined:
        return predefined[label]

    import hashlib
    hash_val = int(hashlib.md5(label.encode('utf-8')).hexdigest(), 16)
    hue = hash_val % 360
    
    s, l = 0.65, 0.50
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((hue / 60) % 2 - 1))
    m = l - c / 2
    
    if 0 <= hue < 60:
        r, g, b = c, x, 0
    elif 60 <= hue < 120:
        r, g, b = x, c, 0
    elif 120 <= hue < 180:
        r, g, b = 0, c, x
    elif 180 <= hue < 240:
        r, g, b = 0, x, c
    elif 240 <= hue < 300:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x
        
    return f"#{int((r + m) * 255):02X}{int((g + m) * 255):02X}{int((b + m) * 255):02X}"


def enrich_entries(entries):
    enriched = []
    for entry in entries:
        item = dict(entry)
        item['tech_stack'] = extract_tech(entry)
        item['tech_color'] = stack_color(item['tech_stack'])
        item['domain'] = extract_domain(entry)
        item['domain_color'] = domain_color(item['domain'])
        enriched.append(item)
    return enriched


def distribution_for(entries):
    total = len(entries)
    counts = Counter(entry['tech_stack'] for entry in entries)
    return [
        {
            'tech': tech,
            'count': count,
            'percentage': round((count / total) * 100) if total else 0,
            'color': stack_color(tech),
        }
        for tech, count in counts.most_common()
    ]


def domain_distribution_for(entries):
    total = len(entries)
    counts = Counter(entry['domain'] for entry in entries)
    result = []
    for domain, count in counts.most_common():
        domain_entries = [e for e in entries if e['domain'] == domain]
        top_stacks = Counter(e['tech_stack'] for e in domain_entries).most_common(2)
        stack_str = ', '.join(s[0] for s in top_stacks) if top_stacks else 'General'
        pct = round((count / total) * 100) if total else 0
        result.append({
            'domain': domain,
            'count': count,
            'percentage': pct,
            'color': domain_color(domain),
            'top_stacks': stack_str,
            'trend_status': 'Popular' if pct >= 35 else ('Emerging' if pct >= 15 else 'Steady'),
        })
    return result


def get_available_rubrics(academic_year=None, scope=None):
    """
    Returns list of real rubrics from database for the admin filter dropdown.
    Supports filtering by academic year and scope (capstone vs pit).
    """
    qs = Rubric.objects.select_related('semester', 'defense_stage').all()
    if academic_year:
        qs = qs.filter(semester__school_year__label=academic_year)
    if scope and scope != 'all':
        qs = qs.filter(scope=scope)

    rubrics = []
    for r in qs:
        rubrics.append({
            'id': str(r.id),
            'name': r.name,
            'scope': r.scope,
            'stage': r.defense_stage.label if r.defense_stage else (r.context_label or 'All Stages'),
            'evaluation_type': r.get_evaluation_type_display(),
            'criteria_count': r.criteria.count(),
            'status': r.status,
        })
    return rubrics


def get_available_stages(scope=None):
    """
    Returns real configured defense stages and PIT events for filtering.
    """
    stages = []
    include_capstone = scope in [None, 'all', 'capstone']
    include_pit = scope in [None, 'all', 'pit']

    if include_capstone:
        for s in DefenseStage.objects.filter(is_active=True).order_by('display_order'):
            stages.append({
                'id': str(s.id),
                'label': s.label,
                'code': s.code,
                'track': 'capstone',
                'display_order': s.display_order,
            })

    if include_pit:
        pit_configs = PitEventGradingConfig.objects.all().order_by('event_name')
        seen_names = set()
        for p in pit_configs:
            if p.event_name not in seen_names:
                seen_names.add(p.event_name)
                stages.append({
                    'id': f'pit-{p.id}',
                    'label': p.event_name,
                    'code': p.event_code or p.event_name[:10].upper(),
                    'track': 'pit',
                    'display_order': 100 + len(seen_names),
                })
        
        pit_labels = TeamGrade.objects.filter(scope=TeamGrade.SCOPE_PIT).values_list('stage_label', flat=True).distinct()
        for pl in pit_labels:
            if pl and pl not in seen_names and pl != 'Unscheduled':
                seen_names.add(pl)
                stages.append({
                    'id': f'pit-{pl.lower().replace(" ", "-")}',
                    'label': pl,
                    'code': pl[:10].upper(),
                    'track': 'pit',
                    'display_order': 100 + len(seen_names),
                })

    return stages


def _compute_evaluator_breakdown(matching_breakdowns):
    breakdown = {}
    for eval_type in ['panel', 'adviser', 'peer']:
        type_scores = [
            float(b.normalized_score)
            for b in matching_breakdowns
            if b.evaluation_type == eval_type and b.max_score > 0
        ]
        if type_scores:
            breakdown[eval_type] = {
                'score': round(sum(type_scores) / len(type_scores), 1),
                'count': len(type_scores),
            }
        else:
            breakdown[eval_type] = {
                'score': None,
                'count': 0,
            }
    return breakdown


def _compute_stage_breakdown(matching_breakdowns):
    stage_scores_map = defaultdict(list)
    for b in matching_breakdowns:
        if b.max_score > 0:
            stage_name = 'General'
            if b.team_grade_id:
                if b.team_grade.defense_stage_id and b.team_grade.defense_stage:
                    stage_name = b.team_grade.defense_stage.label
                elif b.team_grade.stage_label:
                    stage_name = b.team_grade.stage_label
            elif b.rubric_id and b.rubric:
                if b.rubric.defense_stage_id and b.rubric.defense_stage:
                    stage_name = b.rubric.defense_stage.label
                elif b.rubric.context_label:
                    stage_name = b.rubric.context_label
            stage_scores_map[stage_name].append(float(b.normalized_score))
    
    stages_list = []
    for stage_name, s_scores in stage_scores_map.items():
        if s_scores:
            stages_list.append({
                'stage': stage_name,
                'score': round(sum(s_scores) / len(s_scores), 1),
                'count': len(s_scores),
            })
    return stages_list


def stage_performance_overview_for(academic_year=None, scope=None):
    """
    Computes macro stage-by-stage comparison metrics for the Decision Cockpit.
    Compares Panelist, Adviser, and Peer scores across Capstone defense stages and PIT events.
    """
    include_capstone = scope in [None, 'all', 'capstone']
    include_pit = scope in [None, 'all', 'pit']

    grades_qs = TeamGrade.objects.select_related(
        'defense_stage', 'pit_event_config', 'semester', 'semester__school_year'
    ).all()
    if academic_year:
        grades_qs = grades_qs.filter(semester__school_year__label=academic_year)
    if scope and scope != 'all':
        grades_qs = grades_qs.filter(scope=scope)

    breakdowns_qs = GradeBreakdown.objects.select_related(
        'team_grade', 'team_grade__defense_stage', 'rubric'
    ).all()
    if academic_year:
        breakdowns_qs = breakdowns_qs.filter(team_grade__semester__school_year__label=academic_year)

    stage_matrix = []

    # 1. Capstone Stages
    if include_capstone:
        capstone_stages = DefenseStage.objects.filter(is_active=True).order_by('display_order')
        for stage in capstone_stages:
            stage_grades = grades_qs.filter(
                Q(defense_stage=stage) | Q(stage_label__iexact=stage.label)
            )
            total_teams = stage_grades.count()
            
            panel_grades = [float(g.panel_score) for g in stage_grades if g.panel_score is not None]
            adviser_grades = [float(g.adviser_score) for g in stage_grades if g.adviser_score is not None]
            peer_grades = [float(g.peer_score) for g in stage_grades if g.peer_score is not None]
            final_grades = [float(g.final_grade) for g in stage_grades if g.final_grade is not None]

            stage_breakdowns = breakdowns_qs.filter(
                Q(team_grade__defense_stage=stage) | Q(team_grade__stage_label__iexact=stage.label) | Q(rubric__defense_stage=stage)
            )
            if not panel_grades and stage_breakdowns.exists():
                panel_scores = [float(b.normalized_score) for b in stage_breakdowns if b.evaluation_type == 'panel' and b.max_score > 0]
                if panel_scores:
                    panel_grades = panel_scores
                adviser_scores = [float(b.normalized_score) for b in stage_breakdowns if b.evaluation_type == 'adviser' and b.max_score > 0]
                if adviser_scores:
                    adviser_grades = adviser_scores
                peer_scores = [float(b.normalized_score) for b in stage_breakdowns if b.evaluation_type == 'peer' and b.max_score > 0]
                if peer_scores:
                    peer_grades = peer_scores

            panel_avg = round(sum(panel_grades) / len(panel_grades), 1) if panel_grades else None
            adviser_avg = round(sum(adviser_grades) / len(adviser_grades), 1) if adviser_grades else None
            peer_avg = round(sum(peer_grades) / len(peer_grades), 1) if peer_grades else None
            
            all_stage_scores = final_grades or (panel_grades + adviser_grades + peer_grades)
            stage_avg = round(sum(all_stage_scores) / len(all_stage_scores), 1) if all_stage_scores else None

            passed_count = stage_grades.filter(verdict__in=[TeamGrade.VERDICT_APPROVED, TeamGrade.VERDICT_APPROVED_WITH_REVISIONS]).count()
            pass_rate = round((passed_count / total_teams) * 100) if total_teams else 0

            rubrics_in_stage = Rubric.objects.filter(defense_stage=stage)
            criteria_count = RubricCriterion.objects.filter(rubric__in=rubrics_in_stage).count()

            stage_matrix.append({
                'stage_id': str(stage.id),
                'stage_name': stage.label,
                'track': 'capstone',
                'track_label': 'Capstone',
                'code': stage.code,
                'display_order': stage.display_order,
                'total_teams': total_teams,
                'average_score': stage_avg,
                'evaluator_breakdown': {
                    'panel': {'score': panel_avg, 'count': len(panel_grades)},
                    'adviser': {'score': adviser_avg, 'count': len(adviser_grades)},
                    'peer': {'score': peer_avg, 'count': len(peer_grades)},
                },
                'score_spread': {
                    'min': round(min(all_stage_scores), 1) if all_stage_scores else None,
                    'avg': stage_avg,
                    'max': round(max(all_stage_scores), 1) if all_stage_scores else None,
                },
                'pass_rate': pass_rate,
                'rubrics_count': rubrics_in_stage.count(),
                'criteria_count': criteria_count,
                'status': 'Evaluated' if total_teams > 0 else 'Awaiting Hearings',
            })

    # 2. PIT Events
    if include_pit:
        pit_grades_all = grades_qs.filter(scope=TeamGrade.SCOPE_PIT)
        pit_labels = list(pit_grades_all.values_list('stage_label', flat=True).distinct())
        for cfg in PitEventGradingConfig.objects.all():
            if cfg.event_name not in pit_labels:
                pit_labels.append(cfg.event_name)

        for pit_label in pit_labels:
            if not pit_label or pit_label == 'Unscheduled':
                continue
            stage_grades = pit_grades_all.filter(stage_label__iexact=pit_label)
            total_teams = stage_grades.count()

            panel_grades = [float(g.panel_score) for g in stage_grades if g.panel_score is not None]
            adviser_grades = [float(g.adviser_score) for g in stage_grades if g.adviser_score is not None]
            peer_grades = [float(g.peer_score) for g in stage_grades if g.peer_score is not None]
            final_grades = [float(g.final_grade) for g in stage_grades if g.final_grade is not None]

            panel_avg = round(sum(panel_grades) / len(panel_grades), 1) if panel_grades else None
            adviser_avg = round(sum(adviser_grades) / len(adviser_grades), 1) if adviser_grades else None
            peer_avg = round(sum(peer_grades) / len(peer_grades), 1) if peer_grades else None

            all_stage_scores = final_grades or (panel_grades + adviser_grades + peer_grades)
            stage_avg = round(sum(all_stage_scores) / len(all_stage_scores), 1) if all_stage_scores else None

            passed_count = stage_grades.filter(verdict__in=[TeamGrade.VERDICT_APPROVED, TeamGrade.VERDICT_APPROVED_WITH_REVISIONS]).count()
            pass_rate = round((passed_count / total_teams) * 100) if total_teams else 0

            stage_matrix.append({
                'stage_id': f'pit-{pit_label.lower().replace(" ", "-")}',
                'stage_name': pit_label,
                'track': 'pit',
                'track_label': 'PIT',
                'code': pit_label[:10].upper(),
                'display_order': 100 + len(stage_matrix),
                'total_teams': total_teams,
                'average_score': stage_avg,
                'evaluator_breakdown': {
                    'panel': {'score': panel_avg, 'count': len(panel_grades)},
                    'adviser': {'score': adviser_avg, 'count': len(adviser_grades)},
                    'peer': {'score': peer_avg, 'count': len(peer_grades)},
                },
                'score_spread': {
                    'min': round(min(all_stage_scores), 1) if all_stage_scores else None,
                    'avg': stage_avg,
                    'max': round(max(all_stage_scores), 1) if all_stage_scores else None,
                },
                'pass_rate': pass_rate,
                'rubrics_count': 1,
                'criteria_count': 0,
                'status': 'Evaluated' if total_teams > 0 else 'Awaiting Pitch',
            })

    return stage_matrix


def dynamic_criteria_matrix_for(academic_year=None, rubric_id=None, stage_id=None, scope=None):
    """
    Dynamically queries actual RubricCriterion models and computes evaluation metrics from GradeBreakdown.
    Calculates Evaluator Divergence (|Panel - Adviser|) and maps to prerequisite courses.
    Supports academic year, rubric, stage, and scope filtering.
    """
    is_all = not rubric_id or rubric_id == 'all'
    
    criteria_qs = RubricCriterion.objects.select_related('rubric', 'rubric__defense_stage')
    if not is_all:
        criteria_qs = criteria_qs.filter(rubric_id=rubric_id)
    elif academic_year:
        criteria_qs = criteria_qs.filter(rubric__semester__school_year__label=academic_year)

    if scope and scope != 'all':
        criteria_qs = criteria_qs.filter(rubric__scope=scope)

    if stage_id and stage_id != 'all':
        criteria_qs = criteria_qs.filter(
            Q(rubric__defense_stage_id=stage_id) | Q(rubric__defense_stage__label__iexact=stage_id) | Q(rubric__context_label__icontains=stage_id)
        )

    if not criteria_qs.exists():
        criteria_qs = RubricCriterion.objects.select_related('rubric', 'rubric__defense_stage').all()

    breakdowns_qs = GradeBreakdown.objects.select_related(
        'team_grade',
        'team_grade__defense_stage',
        'rubric',
        'rubric__defense_stage',
    ).all()
    if academic_year:
        breakdowns_qs = breakdowns_qs.filter(team_grade__semester__school_year__label=academic_year)
    if not is_all:
        breakdowns_qs = breakdowns_qs.filter(rubric_id=rubric_id)
    if scope and scope != 'all':
        breakdowns_qs = breakdowns_qs.filter(Q(team_grade__scope=scope) | Q(rubric__scope=scope))
    if stage_id and stage_id != 'all':
        breakdowns_qs = breakdowns_qs.filter(
            Q(team_grade__defense_stage_id=stage_id) | Q(team_grade__stage_label__iexact=stage_id) | Q(rubric__defense_stage_id=stage_id)
        )

    # Also aggregate peer evaluation submissions for criteria breakdown
    peer_submissions_qs = PeerEvaluationSubmission.objects.select_related(
        'team_grade',
        'team_grade__semester',
        'team_grade__semester__school_year',
        'team_grade__defense_stage',
    ).all()
    if academic_year:
        peer_submissions_qs = peer_submissions_qs.filter(team_grade__semester__school_year__label=academic_year)
    if scope and scope != 'all':
        peer_submissions_qs = peer_submissions_qs.filter(team_grade__scope=scope)
    if stage_id and stage_id != 'all':
        peer_submissions_qs = peer_submissions_qs.filter(
            Q(team_grade__defense_stage_id=stage_id) | Q(team_grade__stage_label__iexact=stage_id)
        )

    class PeerBreakdownAdapter:
        def __init__(self, criterion_name, normalized_score, max_score, team_grade):
            self.evaluation_type = 'peer'
            self.criterion_name = criterion_name
            self.normalized_score = normalized_score
            self.max_score = max_score
            self.team_grade = team_grade
            self.team_grade_id = team_grade.id if team_grade else None
            self.rubric_id = None
            self.rubric = None

    peer_breakdowns = []
    # If filtered to a specific rubric, only include peer submissions if that rubric is of type peer
    allow_peer = True
    if not is_all:
        try:
            target_rubric = Rubric.objects.filter(id=rubric_id).first()
            if target_rubric and target_rubric.evaluation_type != Rubric.EVAL_PEER:
                allow_peer = False
        except Exception:
            pass

    if allow_peer:
        for sub in peer_submissions_qs:
            for b in (sub.breakdown or []):
                crit_name = b.get('criteriaName') or b.get('name') or b.get('criterion_name')
                if not crit_name:
                    continue
                try:
                    b_max = float(b.get('max', 0) or b.get('max_score', 0))
                    b_score = float(b.get('score', 0))
                    if b_max > 0:
                        norm = (b_score / b_max) * 100.0
                        peer_breakdowns.append(
                            PeerBreakdownAdapter(
                                criterion_name=str(crit_name).strip(),
                                normalized_score=norm,
                                max_score=b_max,
                                team_grade=sub.team_grade,
                            )
                        )
                except (ValueError, TypeError):
                    continue

    matrix = []

    if is_all:
        grouped_criteria = defaultdict(list)
        for c in criteria_qs.order_by('display_order', 'id'):
            key = c.name.strip()
            grouped_criteria[key].append(c)

        for name, criteria_list in grouped_criteria.items():
            first_c = criteria_list[0]
            rubric_names = sorted(list({c.rubric.name for c in criteria_list if c.rubric}))
            rubric_str = ', '.join(rubric_names)
            
            matching_breakdowns = list(breakdowns_qs.filter(
                criterion_name__iexact=name
            ))
            matching_breakdowns.extend([
                pb for pb in peer_breakdowns
                if pb.criterion_name.lower() == name.lower()
            ])
            scores = [float(b.normalized_score) for b in matching_breakdowns if b.max_score > 0]
            eval_count = len(scores)

            evaluator_breakdown = _compute_evaluator_breakdown(matching_breakdowns)
            stage_breakdown = _compute_stage_breakdown(matching_breakdowns)

            divergence = None
            divergence_status = 'Aligned'
            present_eval_scores = [v['score'] for v in evaluator_breakdown.values() if v['score'] is not None]
            if len(present_eval_scores) >= 2:
                diff = round(max(present_eval_scores) - min(present_eval_scores), 1)
                divergence = diff
                if diff >= 15.0:
                    divergence_status = f'High Divergence ({diff}%)'
                elif diff >= 8.0:
                    divergence_status = f'Moderate Divergence ({diff}%)'
                else:
                    divergence_status = f'Aligned (±{diff}%)'

            if eval_count > 0:
                avg_score = round(sum(scores) / eval_count, 1)
                min_score = round(min(scores), 1)
                max_score = round(max(scores), 1)
                is_proficient = avg_score >= 75.0
                delta = round(avg_score - 75.0, 1)
                if avg_score >= 80.0:
                    status = 'Good (80%+)'
                    color = '#10B981'
                elif avg_score >= 75.0:
                    status = 'Passing (75-79%)'
                    color = '#F59E0B'
                else:
                    status = 'Needs Focus (<75%)'
                    color = '#EF4444'
            else:
                avg_score = None
                min_score = None
                max_score = None
                is_proficient = None
                delta = None
                status = 'No Grades Yet'
                color = '#94A3B8'

            c_stage_id = str(first_c.rubric.defense_stage_id) if (first_c.rubric and first_c.rubric.defense_stage_id) else ''
            c_stage_name = first_c.rubric.defense_stage.label if (first_c.rubric and first_c.rubric.defense_stage) else (first_c.rubric.context_label if first_c.rubric else 'General')

            matrix.append({
                'id': f'group-{first_c.id}',
                'criterion_id': first_c.id,
                'name': name,
                'rubric_name': f'Used in {len(rubric_names)} Rubrics ({rubric_str})' if len(rubric_names) > 1 else rubric_str,
                'rubric_id': 'all',
                'stage_id': c_stage_id,
                'stage_name': c_stage_name,
                'stage_label': c_stage_name,
                'weight': None,
                'max_score': first_c.max_score,
                'scale': first_c.scale,
                'evaluations_count': eval_count,
                'average_score': avg_score,
                'score': avg_score,
                'min_score': min_score,
                'max_score': max_score,
                'benchmark': 75.0,
                'delta': delta,
                'is_proficient': is_proficient,
                'status': status,
                'color': color,
                'evaluator_breakdown': evaluator_breakdown,
                'stage_breakdown': stage_breakdown,
                'divergence': divergence,
                'divergence_status': divergence_status,
                'score_spread': {
                    'min': min_score,
                    'avg': avg_score,
                    'max': max_score,
                },
            })
    else:
        for criterion in criteria_qs.order_by('display_order', 'id'):
            matching_breakdowns = list(breakdowns_qs.filter(
                Q(criterion_name__iexact=criterion.name) | Q(rubric=criterion.rubric, criterion_name__icontains=criterion.name)
            ))
            matching_breakdowns.extend([
                pb for pb in peer_breakdowns
                if pb.criterion_name.lower() == criterion.name.strip().lower()
            ])
            scores = [float(b.normalized_score) for b in matching_breakdowns if b.max_score > 0]
            eval_count = len(scores)

            evaluator_breakdown = _compute_evaluator_breakdown(matching_breakdowns)
            stage_breakdown = _compute_stage_breakdown(matching_breakdowns)
            present_eval_scores = [v['score'] for v in evaluator_breakdown.values() if v['score'] is not None]
            divergence = None
            divergence_status = 'Aligned'
            if len(present_eval_scores) >= 2:
                diff = round(max(present_eval_scores) - min(present_eval_scores), 1)
                divergence = diff
                if diff >= 15.0:
                    divergence_status = f'High Divergence ({diff}%)'
                elif diff >= 8.0:
                    divergence_status = f'Moderate Divergence ({diff}%)'
                else:
                    divergence_status = f'Aligned (±{diff}%)'

            if scores:
                avg_score = round(sum(scores) / eval_count, 1)
                min_score = round(min(scores), 1)
                max_score = round(max(scores), 1)
                is_proficient = avg_score >= 75.0
                delta = round(avg_score - 75.0, 1)
                if avg_score >= 85.0:
                    status = 'Strong (85%+)'
                    color = '#10B981'
                elif avg_score >= 75.0:
                    status = 'Proficient (75-84%)'
                    color = '#F59E0B'
                else:
                    status = 'Needs Focus (<75%)'
                    color = '#EF4444'
            else:
                avg_score = None
                min_score = None
                max_score = None
                is_proficient = None
                delta = None
                status = 'No Grades Yet'
                color = '#94A3B8'

            c_stage_id = str(criterion.rubric.defense_stage_id) if (criterion.rubric and criterion.rubric.defense_stage_id) else ''
            c_stage_name = criterion.rubric.defense_stage.label if (criterion.rubric and criterion.rubric.defense_stage) else (criterion.rubric.context_label if criterion.rubric else 'General')

            matrix.append({
                'id': str(criterion.id),
                'criterion_id': criterion.id,
                'name': criterion.name,
                'rubric_name': criterion.rubric.name if criterion.rubric else 'Rubric',
                'rubric_id': str(criterion.rubric.id) if criterion.rubric else '',
                'stage_id': c_stage_id,
                'stage_name': c_stage_name,
                'stage_label': c_stage_name,
                'weight': float(criterion.weight) if criterion.weight else None,
                'max_score': criterion.max_score,
                'scale': criterion.scale,
                'evaluations_count': eval_count,
                'average_score': avg_score,
                'score': avg_score,
                'min_score': min_score,
                'max_score': max_score,
                'benchmark': 75.0,
                'delta': delta,
                'is_proficient': is_proficient,
                'status': status,
                'color': color,
                'evaluator_breakdown': evaluator_breakdown,
                'stage_breakdown': stage_breakdown,
                'divergence': divergence,
                'divergence_status': divergence_status,
                'score_spread': {
                    'min': min_score,
                    'avg': avg_score,
                    'max': max_score,
                },
            })

    return matrix


def evaluator_calibration_overview_for(academic_year=None, scope=None):
    """
    Model Management Subsystem: Evaluator Discrepancy & Calibration Model.
    Computes absolute scoring variance between Panelists and Advisers (|Panel - Adviser|).
    """
    grades_qs = TeamGrade.objects.select_related('semester', 'semester__school_year').all()
    if academic_year:
        grades_qs = grades_qs.filter(semester__school_year__label=academic_year)
    if scope and scope != 'all':
        grades_qs = grades_qs.filter(scope=scope)

    divergence_pairs = []
    adviser_higher_count = 0
    panel_higher_count = 0
    equal_count = 0

    for g in grades_qs:
        if g.panel_score is not None and g.adviser_score is not None:
            p = float(g.panel_score)
            a = float(g.adviser_score)
            diff = a - p
            divergence_pairs.append(abs(diff))
            if diff > 1.0:
                adviser_higher_count += 1
            elif diff < -1.0:
                panel_higher_count += 1
            else:
                equal_count += 1

    total_pairs = len(divergence_pairs)
    mean_divergence = round(sum(divergence_pairs) / total_pairs, 1) if total_pairs else 0.0
    adviser_leniency_pct = round((adviser_higher_count / total_pairs) * 100) if total_pairs else 0

    if mean_divergence >= 15.0:
        status = 'High Discrepancy'
        status_color = '#EF4444'
        diagnosis = 'Advisers and Panelists exhibit significant scoring divergence (>15%). Rubric calibration is recommended.'
    elif mean_divergence >= 8.0:
        status = 'Moderate Divergence'
        status_color = '#F59E0B'
        diagnosis = 'Acceptable scoring spread, though individual criteria show variance.'
    else:
        status = 'Well Calibrated'
        status_color = '#10B981'
        diagnosis = 'Panelists and Advisers exhibit consistent, synchronized scoring standards.'

    return {
        'total_evaluated_teams': total_pairs,
        'mean_divergence': mean_divergence,
        'adviser_higher_count': adviser_higher_count,
        'panel_higher_count': panel_higher_count,
        'equal_count': equal_count,
        'adviser_leniency_rate': adviser_leniency_pct,
        'calibration_status': status,
        'calibration_color': status_color,
        'diagnosis': diagnosis,
    }


def simulate_policy_scenarios(academic_year=None, scope=None):
    """
    Model Management Subsystem: What-If Policy Simulation Model.
    Simulates projected pass rates under different benchmark thresholds and evaluator weight models.
    """
    grades_qs = TeamGrade.objects.filter(final_grade__isnull=False)
    if academic_year:
        grades_qs = grades_qs.filter(semester__school_year__label=academic_year)
    if scope and scope != 'all':
        grades_qs = grades_qs.filter(scope=scope)

    final_scores = [float(g.final_grade) for g in grades_qs]
    total = len(final_scores)

    benchmark_scenarios = []
    for bm in [70.0, 75.0, 80.0, 85.0]:
        passed = sum(1 for s in final_scores if s >= bm)
        rate = round((passed / total) * 100) if total else 0
        benchmark_scenarios.append({
            'threshold': bm,
            'projected_pass_rate': rate,
            'passed_count': passed,
            'failed_count': total - passed,
            'is_current': (bm == 75.0),
        })

    weight_models = [
        {'name': 'Standard Policy', 'panel': 0.50, 'adviser': 0.30, 'peer': 0.20, 'is_active': True},
        {'name': 'Panel-Priority', 'panel': 0.70, 'adviser': 0.20, 'peer': 0.10, 'is_active': False},
        {'name': 'Balanced Adviser/Panel', 'panel': 0.40, 'adviser': 0.40, 'peer': 0.20, 'is_active': False},
        {'name': 'Equal Triad', 'panel': 0.34, 'adviser': 0.33, 'peer': 0.33, 'is_active': False},
    ]

    weight_scenarios = []
    for wm in weight_models:
        simulated_scores = []
        for g in grades_qs:
            p = float(g.panel_score) if g.panel_score is not None else float(g.final_grade)
            a = float(g.adviser_score) if g.adviser_score is not None else p
            pe = float(g.peer_score) if g.peer_score is not None else p
            sim_score = (p * wm['panel']) + (a * wm['adviser']) + (pe * wm['peer'])
            simulated_scores.append(sim_score)

        sim_avg = round(sum(simulated_scores) / len(simulated_scores), 1) if simulated_scores else 0.0
        sim_pass = sum(1 for s in simulated_scores if s >= 75.0)
        sim_rate = round((sim_pass / len(simulated_scores)) * 100) if simulated_scores else 0

        weight_scenarios.append({
            'model_name': wm['name'],
            'weights': f"{int(wm['panel']*100)}% Panel / {int(wm['adviser']*100)}% Adviser / {int(wm['peer']*100)}% Peer",
            'simulated_average': sim_avg,
            'simulated_pass_rate': sim_rate,
            'is_active': wm['is_active'],
        })

    return {
        'total_simulated_teams': total,
        'benchmark_scenarios': benchmark_scenarios,
        'weight_scenarios': weight_scenarios,
    }


def defense_funnel_for(academic_year=None, scope=None):
    """
    Computes real stage-by-stage defense outcomes from DefenseStage / PIT events and TeamGrade.
    Generates exact counts, percentages, and verdict distribution for Pie/Donut charts.
    Includes Operational Friction Index: (redefense_rate * 2) + revision_rate.
    """
    grades_qs = TeamGrade.objects.select_related('defense_stage', 'semester', 'semester__school_year').all()
    if academic_year:
        grades_qs = grades_qs.filter(semester__school_year__label=academic_year)
    if scope and scope != 'all':
        grades_qs = grades_qs.filter(scope=scope)

    include_capstone = scope in [None, 'all', 'capstone']
    include_pit = scope in [None, 'all', 'pit']

    funnel_stages = []
    total_approved = 0
    total_revisions = 0
    total_redefense = 0
    total_pending = 0

    stages_to_evaluate = []
    if include_capstone:
        for s in DefenseStage.objects.filter(is_active=True).order_by('display_order'):
            stages_to_evaluate.append((str(s.id), s.label, s.code, 'capstone', Q(defense_stage=s) | Q(stage_label__iexact=s.label)))

    if include_pit:
        pit_grades = grades_qs.filter(scope=TeamGrade.SCOPE_PIT)
        pit_labels = list(pit_grades.values_list('stage_label', flat=True).distinct())
        for cfg in PitEventGradingConfig.objects.all():
            if cfg.event_name not in pit_labels:
                pit_labels.append(cfg.event_name)
        for pl in pit_labels:
            if pl and pl != 'Unscheduled':
                stages_to_evaluate.append((f'pit-{pl.lower().replace(" ", "-")}', pl, pl[:10].upper(), 'pit', Q(stage_label__iexact=pl)))

    for stage_id, stage_name, code, track, query_filter in stages_to_evaluate:
        stage_grades = grades_qs.filter(query_filter)
        count = stage_grades.count()

        approved = stage_grades.filter(verdict=TeamGrade.VERDICT_APPROVED).count()
        with_rev = stage_grades.filter(verdict=TeamGrade.VERDICT_APPROVED_WITH_REVISIONS).count()
        redef = stage_grades.filter(verdict=TeamGrade.VERDICT_FOR_REDEFENSE).count()
        pending = stage_grades.filter(Q(verdict='') | Q(status=TeamGrade.STATUS_PENDING)).count()

        total_approved += approved
        total_revisions += with_rev
        total_redefense += redef
        total_pending += pending

        app_pct = round((approved / count) * 100) if count else 0
        rev_pct = round((with_rev / count) * 100) if count else 0
        redef_pct = round((redef / count) * 100) if count else 0
        pend_pct = round((pending / count) * 100) if count else 0

        friction_index = round((redef_pct * 2.0) + rev_pct, 1)

        funnel_stages.append({
            'stage_id': str(stage_id),
            'stage_name': stage_name,
            'track': track,
            'code': code,
            'total_teams': count,
            'approved_count': approved,
            'revisions_count': with_rev,
            'redefense_count': redef,
            'pending_count': pending,
            'first_pass_rate': app_pct,
            'revision_rate': rev_pct,
            'redefense_rate': redef_pct,
            'pending_rate': pend_pct,
            'friction_index': friction_index,
            'status_label': f"{app_pct}% Passed · {rev_pct}% Revisions" if count else "No hearings yet",
        })

    grand_total = grades_qs.count() or sum(f['total_teams'] for f in funnel_stages) or 1
    verdicts_pie = [
        {
            'label': 'Passed (1st Try)',
            'count': total_approved,
            'percentage': round((total_approved / grand_total) * 100) if grand_total else 0,
            'color': '#10B981',
        },
        {
            'label': 'Needs Revisions',
            'count': total_revisions,
            'percentage': round((total_revisions / grand_total) * 100) if grand_total else 0,
            'color': '#F59E0B',
        },
        {
            'label': 'For Re-Defense',
            'count': total_redefense,
            'percentage': round((total_redefense / grand_total) * 100) if grand_total else 0,
            'color': '#EF4444',
        },
        {
            'label': 'Pending Hearing',
            'count': total_pending,
            'percentage': round((total_pending / grand_total) * 100) if grand_total else 0,
            'color': '#94A3B8',
        },
    ]

    bottleneck = 'None Identified'
    bottleneck_reason = 'All evaluated stages demonstrate smooth milestone progression.'
    max_friction = -1
    for f in funnel_stages:
        if f['total_teams'] > 0 and (f['redefense_count'] > 0 or f['revisions_count'] > 0):
            if f['friction_index'] > max_friction:
                max_friction = f['friction_index']
                bottleneck = f['stage_name']
                if f['redefense_rate'] > 20:
                    bottleneck_reason = f"High re-defense rate ({f['redefense_rate']}%) indicates structural gaps."
                else:
                    bottleneck_reason = f"Heavy revision burden ({f['revision_rate']}%) requiring panel follow-up."

    return {
        'total_evaluated': grades_qs.count(),
        'stages': funnel_stages,
        'verdicts_distribution': verdicts_pie,
        'bottleneck_stage': bottleneck,
        'bottleneck_reason': bottleneck_reason,
        'max_friction': max_friction if max_friction >= 0 else 0,
    }


def longitudinal_5year_for(entries):
    """
    Builds real historical progression grouped by academic years recorded in the system.
    """
    by_year = defaultdict(list)
    for entry in entries:
        by_year[entry.get('academic_year') or 'Unknown'].append(entry)

    recorded_years = sorted([y for y in by_year.keys() if y and y != 'Unknown'])
    if not recorded_years:
        recorded_years = ['2026-2027']

    series = []
    for ay in recorded_years:
        year_entries = by_year.get(ay, [])
        tech_dist = distribution_for(year_entries) if year_entries else []
        dom_dist = domain_distribution_for(year_entries) if year_entries else []
        
        top_t = tech_dist[0]['tech'] if tech_dist else 'Unclassified'
        top_d = dom_dist[0]['domain'] if dom_dist else 'General Systems'
        
        year_grades = TeamGrade.objects.filter(semester__school_year__label=ay, final_grade__isnull=False)
        avg_g = year_grades.aggregate(Avg('final_grade'))['final_grade__avg']
        grade_val = round(float(avg_g), 1) if avg_g is not None else 80.0

        series.append({
            'academic_year': ay,
            'total_projects': len(year_entries),
            'competency_index': grade_val,
            'top_tech': top_t,
            'top_domain': top_d,
            'tech_distribution': tech_dist[:4],
            'domain_distribution': dom_dist[:4],
        })

    return series


def prescriptive_actions_for(entries, breakdown, competencies, funnel, trends, calibration=None, scope=None):
    """
    Knowledge-Based Subsystem (KBS): Generates concrete, prioritized administrative directives.
    Transforms data points into actionable institutional decisions for PIT, Capstone, and Curriculum.
    """
    actions = []

    # 1. Criteria Needing Focus (<75% passing benchmark)
    evaluated_comps = [c for c in competencies if c.get('average_score') is not None]
    low_criteria = [c for c in evaluated_comps if c.get('average_score', 100) < 75.0]
    low_criteria.sort(key=lambda x: x.get('average_score', 0))

    for c in low_criteria[:3]:
        crit_name = c['name']
        avg = c.get('average_score', 0)
        rubric_name = c.get('rubric_name', 'Rubric Criteria')
        actions.append({
            'id': f'criterion-focus-{c.get("criterion_id", crit_name.lower().replace(" ", "-"))}',
            'category': 'rubric_criterion',
            'track': 'capstone' if scope == 'capstone' else ('pit' if scope == 'pit' else 'operations'),
            'type_label': 'Criteria Improvement',
            'severity': 'high' if avg < 70 else 'medium',
            'title': f'Low Performance: {crit_name} ({avg}%)',
            'diagnosis': f'Student teams averaged {avg}% in {crit_name} ({rubric_name}), falling below the 75% passing benchmark.',
            'body': f'Teams are struggling with {crit_name}. Provide additional guidance or sample deliverables before defense hearings.',
            'action_label': f'Review {crit_name} Guidelines',
            'target': crit_name,
        })

    # 2. Defense Pipeline Bottleneck & Friction
    bottleneck = funnel.get('bottleneck_stage')
    if bottleneck and bottleneck != 'None Identified':
        reason = funnel.get('bottleneck_reason', 'High revision or re-defense rate')
        actions.append({
            'id': f'bottleneck-{bottleneck.lower().replace(" ", "-")}',
            'category': 'defense_policy',
            'track': 'capstone' if scope == 'capstone' else ('pit' if scope == 'pit' else 'operations'),
            'type_label': 'Defense Operational Friction',
            'severity': 'high',
            'title': f'Stage Bottleneck: {bottleneck}',
            'diagnosis': reason,
            'body': f'{bottleneck} has the highest operational friction in the cohort. Implementing a mandatory mock hearing with project advisers 10 days prior reduces repeat revisions.',
            'action_label': f'Review {bottleneck} Rubrics & Mock Policy',
            'target': bottleneck,
        })

    # 3. Evaluator Calibration & Grading Discrepancy
    if calibration and calibration.get('mean_divergence', 0) >= 10.0:
        mean_div = calibration['mean_divergence']
        leniency = calibration['adviser_leniency_rate']
        actions.append({
            'id': 'calibration-discrepancy',
            'category': 'faculty_calibration',
            'track': 'calibration',
            'type_label': 'Faculty Grading Integrity',
            'severity': 'high' if mean_div >= 15.0 else 'medium',
            'title': f'Evaluator Scoring Divergence ({mean_div}% Delta)',
            'diagnosis': f'Advisers scored higher than external panelists in {leniency}% of evaluated criteria, indicating possible grading subjectivity.',
            'body': 'External defense panelists and project advisers diverge noticeably in scoring standards. Hold a joint Rubric Calibration Meeting before upcoming hearings.',
            'action_label': 'Schedule Rubric Calibration Meeting',
            'target': 'Faculty & Panelists',
        })

    # 4. Tech Stack Monoculture & Ecosystem Diversity
    top_tech = trends.get('top_tech')
    if breakdown and breakdown[0].get('distribution'):
        top_pct = breakdown[0]['distribution'][0].get('percentage', 0)
        if top_pct >= 50 and top_tech not in ['No data', 'Unclassified']:
            actions.append({
                'id': 'tech-monoculture',
                'category': 'innovation',
                'track': 'curriculum',
                'type_label': 'Project Ecosystem Diversity',
                'severity': 'medium',
                'title': f'High Tech Monoculture: {top_tech} ({top_pct}%)',
                'diagnosis': f'{top_tech} accounts for {top_pct}% of student projects, leaving emerging areas (AI, Cloud, IoT) underrepresented.',
                'body': f'Student projects are disproportionately concentrated in {top_tech}. Introduce approved departmental research themes and workshops in Cloud, Mobile, and AI.',
                'action_label': 'Publish Thematic Track Guidelines',
                'target': 'Capstone & PIT Research Agenda',
            })

    # 5. Default Proficient State
    if not actions:
        if evaluated_comps:
            actions.append({
                'id': 'curriculum-proficient',
                'category': 'status',
                'track': 'all',
                'type_label': 'System Health: Optimal',
                'severity': 'low',
                'title': 'All Cohort Criteria Meet Quality Standards',
                'diagnosis': 'All evaluated rubric dimensions meet or exceed the 75.0% institutional benchmark with calibrated scoring.',
                'body': f'All {len(evaluated_comps)} evaluated rubric criteria meet the standard benchmark. Maintain current curriculum pacing and panelist standards.',
                'action_label': 'Maintain Current Standards',
                'target': 'Academic Curriculum',
            })
        else:
            actions.append({
                'id': 'curriculum-pending',
                'category': 'status',
                'track': 'all',
                'type_label': 'Awaiting Defense Evaluations',
                'severity': 'low',
                'title': 'Ready for Defense Hearings & Panel Scores',
                'diagnosis': 'No published defense evaluations recorded for this cohort selection yet.',
                'body': 'As defense hearings proceed and panelist scorecards are submitted, DefenSYS will automatically diagnose prerequisite course gaps and operational bottlenecks.',
                'action_label': 'Open Defense Operations',
                'target': 'Defense Operations',
            })

    return actions


def analytics_payload(user, academic_year=None, program=None, scope=None, rubric_id=None, stage_id=None):
    ensure_admin(user)
    entries = enrich_entries(source_entries(scope=scope))
    
    academic_years = sorted({entry['academic_year'] for entry in entries if entry.get('academic_year') and entry['academic_year'] != 'Unknown'}, reverse=True)
    if not academic_years:
        academic_years = [sy.label for sy in SchoolYear.objects.all().order_by('-label')] or ['2026-2027']

    selected_year = academic_year or (academic_years[0] if academic_years else '2026-2027')
    
    filtered = [entry for entry in entries if not selected_year or entry['academic_year'] == selected_year]
    if not filtered:
        filtered = entries

    breakdown = year_breakdown(entries)
    trends = trends_payload(entries)
    
    available_rubrics = get_available_rubrics(selected_year, scope=scope)
    available_stages = get_available_stages(scope=scope)
    competencies = dynamic_criteria_matrix_for(academic_year=selected_year, rubric_id=rubric_id, stage_id=stage_id, scope=scope)
    funnel = defense_funnel_for(academic_year=selected_year, scope=scope)
    longitudinal = longitudinal_5year_for(entries)
    domain_dist = domain_distribution_for(filtered)
    calibration = evaluator_calibration_overview_for(academic_year=selected_year, scope=scope)
    simulations = simulate_policy_scenarios(academic_year=selected_year, scope=scope)
    prescriptions = prescriptive_actions_for(filtered, breakdown, competencies, funnel, trends, calibration=calibration, scope=scope)

    evaluated_comps = [c['average_score'] for c in competencies if c['average_score'] is not None]
    if evaluated_comps:
        comp_avg = round(sum(evaluated_comps) / len(evaluated_comps), 1)
    else:
        grades_qs = TeamGrade.objects.filter(
            semester__school_year__label=selected_year, final_grade__isnull=False
        )
        if scope and scope != 'all':
            grades_qs = grades_qs.filter(scope=scope)
        grades_avg = grades_qs.aggregate(Avg('final_grade'))['final_grade__avg']
        comp_avg = round(float(grades_avg), 1) if grades_avg is not None else 0.0

    kpi_summary = {
        'total_projects': len(entries),
        'active_cohort_projects': len(filtered),
        'competency_index': comp_avg,
        'has_evaluations': len(evaluated_comps) > 0 or comp_avg > 0,
        'top_tech': trends['top_tech'],
        'top_domain': domain_dist[0]['domain'] if domain_dist else 'General Software & Systems',
        'top_domain_color': domain_dist[0]['color'] if domain_dist else '#6366F1',
        'bottleneck_stage': funnel['bottleneck_stage'],
        'bottleneck_reason': funnel.get('bottleneck_reason', ''),
        'mean_evaluator_divergence': calibration['mean_divergence'],
        'total_entries': len(entries),
        'rubrics_count': len(available_rubrics),
        'stages_count': len(available_stages),
        'selected_scope': scope or 'all',
    }

    unique_techs = sorted(list({entry['tech_stack'] for entry in entries}))

    return {
        'entries_count': len(entries),
        'selected_academic_year': selected_year,
        'selected_rubric_id': rubric_id or 'all',
        'selected_scope': scope or 'all',
        'metadata_catalog': DSS_METADATA_CATALOG,
        'evaluator_calibration': calibration,
        'simulation_scenarios': simulations,
        'academic_years': academic_years,
        'available_rubrics': available_rubrics,
        'available_stages': available_stages,
        'stage_performance_overview': stage_performance_overview_for(academic_year=selected_year, scope=scope),
        'kpi_summary': kpi_summary,
        'trend_cards': trends,
        'competency_matrix': competencies,
        'domain_distribution': domain_dist,
        'defense_funnel': funnel,
        'longitudinal_5year': longitudinal,
        'prescriptions': prescriptions,
        'suggestions': suggestions_payload(entries, breakdown, trends),
        'distribution': distribution_for(filtered)[:8],
        'year_over_year': breakdown[:3],
        'trend_series': trend_series(entries),
        'recent_entries': entries[:8],
        'taxonomy': [{'label': tech, 'color': stack_color(tech)} for tech in unique_techs],
    }



def year_breakdown(entries):
    by_year = defaultdict(list)
    for entry in entries:
        by_year[entry.get('academic_year') or 'Unknown'].append(entry)
    rows = []
    for year in sorted(by_year.keys(), reverse=True):
        year_entries = by_year[year]
        dist = distribution_for(year_entries)
        top = dist[0] if dist else {'tech': 'No data', 'percentage': 0, 'count': 0}
        rows.append({
            'academic_year': year,
            'total': len(year_entries),
            'top_tech': top['tech'],
            'top_percentage': top['percentage'],
            'distribution': dist[:8],
        })
    return rows


def trend_series(entries):
    breakdown = year_breakdown(entries)
    years = [row['academic_year'] for row in reversed(breakdown)]
    all_techs = sorted(list({entry['tech_stack'] for entry in entries}))
    series = []
    for tech in all_techs:
        points = []
        has_value = False
        for year in years:
            year_entries = [entry for entry in entries if entry['academic_year'] == year]
            total = len(year_entries)
            count = sum(1 for entry in year_entries if entry['tech_stack'] == tech)
            if count:
                has_value = True
            points.append({
                'academic_year': year,
                'count': count,
                'percentage': round((count / total) * 100) if total else 0,
            })
        if has_value:
            series.append({'tech': tech, 'color': stack_color(tech), 'points': points})
    return series


def trends_payload(entries):
    if not entries:
        return {
            'top_tech': 'No data',
            'least_tech': 'No data',
            'top_year_level': 'No data',
            'top_academic_year': 'No data',
            'total_entries': 0,
        }
    tech_counts = Counter(entry['tech_stack'] for entry in entries)
    year_counts = Counter(entry['year_level'] for entry in entries)
    ay_counts = Counter(entry['academic_year'] for entry in entries)
    least = sorted(tech_counts.items(), key=lambda item: (item[1], item[0]))[0]
    return {
        'top_tech': tech_counts.most_common(1)[0][0],
        'least_tech': least[0],
        'top_year_level': year_counts.most_common(1)[0][0],
        'top_academic_year': ay_counts.most_common(1)[0][0],
        'total_entries': len(entries),
    }


def suggestions_payload(entries, breakdown, trends):
    if not entries:
        return [{
            'type': 'info',
            'title': 'No Repository Data Yet',
            'body': 'Upload PIT or Capstone files through Repository Audit to generate curriculum insights.',
        }]
    suggestions = []
    if len(breakdown) >= 2:
        latest = breakdown[0]
        previous = breakdown[1]
        if latest['top_tech'] != previous['top_tech']:
            suggestions.append({
                'type': 'critical',
                'title': 'Technology Shift',
                'body': f'Top technology shifted from {previous["top_tech"]} ({previous["academic_year"]}) to {latest["top_tech"]} ({latest["academic_year"]}).',
            })
    latest_dist = breakdown[0]['distribution'] if breakdown else []
    if latest_dist and latest_dist[0]['percentage'] > 50:
        suggestions.append({
            'type': 'critical',
            'title': 'High Concentration',
            'body': f'{latest_dist[0]["tech"]} accounts for {latest_dist[0]["percentage"]}% of latest projects.',
        })
    if trends['top_year_level'] in ['4th Year', '4thYear']:
        suggestions.append({
            'type': 'success',
            'title': 'Active Project Pipeline',
            'body': '4th Year Capstone projects are actively recorded in the repository.',
        })
    if trends['total_entries'] < 10:
        suggestions.append({
            'type': 'info',
            'title': 'Growing Repository',
            'body': f'{trends["total_entries"]} deliverable files are currently recorded.',
        })
    if not suggestions:
        suggestions.append({
            'type': 'success',
            'title': 'Healthy Curriculum Signals',
            'body': 'Projects span multiple technologies and domains evenly.',
        })
    return suggestions


def proposal_payload(user, academic_year=None, rubric_id=None, scope=None):
    payload = analytics_payload(user, academic_year=academic_year, rubric_id=rubric_id, scope=scope)
    kpis = payload['kpi_summary']
    prescriptions = payload['prescriptions']
    scope_str = "PIT & Capstone" if not scope or scope == 'all' else ("4th Year Capstone" if scope == 'capstone' else "1st-3rd Year PIT")
    
    return {
        'title': f'Curriculum Decision Support Proposal ({scope_str} · AY {payload["selected_academic_year"]})',
        'academic_year': payload['selected_academic_year'],
        'selected_scope': payload.get('selected_scope', 'all'),
        'summary': (
            f'Decision support proposal based on {payload["entries_count"]} {scope_str} project deliverables, '
            f'{len(payload["available_rubrics"])} evaluation rubrics, and defense outcomes for AY {payload["selected_academic_year"]}. '
            f'The leading domain specialization is {kpis["top_domain"]} with {kpis["top_tech"]} as the dominant framework.'
        ),
        'kpi_summary': kpis,
        'competency_matrix': payload['competency_matrix'],
        'domain_distribution': payload['domain_distribution'],
        'evaluator_calibration': payload.get('evaluator_calibration', {}),
        'recommendations': prescriptions,
        'next_steps': [
            'Review student performance in prerequisite courses during the department curriculum meeting.',
            'Incorporate hands-on practice in subjects where students scored below the 75% target.',
            'Hold a mock presentation session before defense hearings to help teams pass on their first try.',
        ],
    }



def analytics_entries_count():
    return len(source_entries())


def analytics_academic_year_count():
    return len({entry['academic_year'] for entry in source_entries() if entry.get('academic_year') and entry['academic_year'] != 'Unknown'})


def analytics_top_tech():
    entries = enrich_entries(source_entries())
    if not entries:
        return 'No data'
    return Counter(entry['tech_stack'] for entry in entries).most_common(1)[0][0]
