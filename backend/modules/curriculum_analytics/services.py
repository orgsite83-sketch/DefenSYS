from collections import Counter, defaultdict

from django.core.exceptions import PermissionDenied

from capstone_deliverables.models import DeliverableSubmission
from capstone_deliverables.services import display_name
from digital_vault.models import VaultEntry


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

DOMAIN_TAXONOMY = [
    {
        'domain': 'Machine Learning / AI',
        'keywords': [
            'predict',
            'ai',
            'machine learning',
            'neural',
            'deep learning',
            'model',
            'training',
            'dataset',
            'classification',
            'regression',
            'nlp',
            'computer vision',
            'tensorflow',
            'pytorch',
            'accuracy',
        ],
    },
    {
        'domain': 'Web Development',
        'keywords': [
            'django',
            'react',
            'vue',
            'angular',
            'laravel',
            'api',
            'rest',
            'frontend',
            'backend',
            'html',
            'css',
            'javascript',
            'node',
            'database',
            'sql',
            'crud',
            'authentication',
        ],
    },
    {
        'domain': 'Mobile Development',
        'keywords': [
            'flutter',
            'android',
            'ios',
            'mobile',
            'dart',
            'kotlin',
            'swift',
            'react native',
            'app',
            'ui',
            'ux',
            'responsive',
        ],
    },
    {
        'domain': 'IoT / Embedded Systems',
        'keywords': [
            'iot',
            'sensor',
            'arduino',
            'raspberry',
            'embedded',
            'firmware',
            'microcontroller',
            'mqtt',
            'smart',
            'automation',
            'hardware',
        ],
    },
    {
        'domain': 'Cybersecurity',
        'keywords': [
            'security',
            'encryption',
            'vulnerability',
            'penetration',
            'firewall',
            'authentication',
            'hash',
            'ssl',
            'threat',
            'audit',
        ],
    },
    {
        'domain': 'Data Analytics / DSS',
        'keywords': [
            'analytics',
            'dashboard',
            'visualization',
            'chart',
            'report',
            'insight',
            'trend',
            'statistics',
            'bi',
            'decision support',
            'data warehouse',
            'etl',
            'tableau',
            'power bi',
        ],
    },
]


def ensure_admin(user):
    if getattr(user, 'role', None) != 'admin' and not getattr(user, 'is_superuser', False):
        raise PermissionDenied('Curriculum analytics is available to admins only.')


def source_entries():
    entries = []
    pit_entries = VaultEntry.objects.select_related('team', 'uploaded_by').filter(
        entry_type=VaultEntry.TYPE_PIT,
    )
    for entry in pit_entries:
        entries.append({
            'id': f'pit-{entry.id}',
            'source_id': entry.id,
            'type': 'pit',
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
        })

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
            'file_name': submission.file_name,
            'team_name': team.name,
            'project_title': team.project_title,
            'deliverable_id': submission.deliverable_id,
            'deliverable_label': submission.label,
            'academic_year': team.semester.school_year.label,
            'year_level': team.year_level,
            'stage': submission.stage_label,
            'status': 'Vault Submission' if submission.deliverable_type == DeliverableSubmission.TYPE_VAULT else 'Pre-Defense',
            'uploaded_by': display_name(submission.uploaded_by) or 'System',
            'uploaded_at': submission.uploaded_at,
        })
    return sorted(entries, key=lambda item: item['uploaded_at'], reverse=True)


def text_for_entry(entry):
    return ' '.join(
        str(entry.get(key) or '')
        for key in [
            'file_name',
            'team_name',
            'project_title',
            'deliverable_label',
            'stage',
            'year_level',
        ]
    ).lower()


def extract_tech(entry):
    text = text_for_entry(entry)
    best = None
    best_score = 0
    for stack in TECH_STACKS:
        score = sum(1 for keyword in stack['keywords'] if keyword in text)
        if score > best_score:
            best = stack
            best_score = score
    if best:
        return best['label']
    if entry.get('type') == 'pit':
        course = (entry.get('stage') or '').upper()
        if course.startswith('PIT1'):
            return 'Django / Python'
        if course.startswith('PIT2'):
            return 'React / Node.js'
        if course.startswith('PIT3'):
            return 'Flutter / Mobile'
    return 'Django / Python'


def stack_color(label):
    return next((item['color'] for item in TECH_STACKS if item['label'] == label), '#6B7280')


def enrich_entries(entries):
    enriched = []
    for entry in entries:
        item = dict(entry)
        item['tech_stack'] = extract_tech(entry)
        item['tech_color'] = stack_color(item['tech_stack'])
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
    all_techs = [item['label'] for item in TECH_STACKS]
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
    return series[:6]


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
                'title': 'Course Shift Detected',
                'body': f'Top technology shifted from {previous["top_tech"]} ({previous["academic_year"]}) to {latest["top_tech"]} ({latest["academic_year"]}). Review course coverage.',
            })
    latest_dist = breakdown[0]['distribution'] if breakdown else []
    if latest_dist and latest_dist[0]['percentage'] > 50:
        suggestions.append({
            'type': 'critical',
            'title': 'Concentration Risk',
            'body': f'{latest_dist[0]["tech"]} accounts for {latest_dist[0]["percentage"]}% of latest uploads. Add variety through elective tracks or project prompts.',
        })
    if trends['top_year_level'] in ['4th Year', '4thYear']:
        suggestions.append({
            'type': 'success',
            'title': 'Capstone Pipeline Is Active',
            'body': '4th Year Capstone has the strongest upload volume. Defense and repository workflows are producing usable analytics data.',
        })
    if trends['total_entries'] < 10:
        suggestions.append({
            'type': 'info',
            'title': 'Low Repository Volume',
            'body': f'Only {trends["total_entries"]} files are available. Encourage repository assistants and advisers to upload all approved deliverables.',
        })
    if not suggestions:
        suggestions.append({
            'type': 'success',
            'title': 'Balanced Curriculum Signals',
            'body': f'{trends["total_entries"]} files span multiple technologies and year levels. Distribution looks healthy for curriculum review.',
        })
    return suggestions


def classify_text(text):
    lower = (text or '').lower()
    scored = []
    for domain in DOMAIN_TAXONOMY:
        hits = []
        score = 0
        for keyword in domain['keywords']:
            count = lower.count(keyword)
            if count:
                hits.append(keyword)
                score += count
        scored.append({'domain': domain['domain'], 'score': score, 'matched_keywords': hits[:6]})
    scored.sort(key=lambda item: item['score'], reverse=True)
    top = scored[0]
    total = sum(item['score'] for item in scored)
    if top['score'] == 0:
        return {'domain': 'Unclassified', 'confidence': 0, 'matched_keywords': []}
    confidence = min(95, round((top['score'] / max(total, 1)) * 100 + 40))
    return {
        'domain': top['domain'],
        'confidence': confidence,
        'matched_keywords': top['matched_keywords'],
    }


def similar_projects(entries, keywords):
    if not keywords:
        return []
    matches = []
    for entry in entries:
        text = text_for_entry(entry)
        score = sum(1 for keyword in keywords if keyword.lower() in text)
        if score:
            matches.append((score, entry))
    matches.sort(key=lambda item: item[0], reverse=True)
    return [
        {
            'file_name': entry['file_name'],
            'team_name': entry['team_name'],
            'project_title': entry.get('project_title') or '',
            'academic_year': entry['academic_year'],
            'type': entry['type'],
            'tech_stack': entry['tech_stack'],
        }
        for _score, entry in matches[:5]
    ]


def analytics_payload(user, academic_year=None):
    ensure_admin(user)
    entries = enrich_entries(source_entries())
    academic_years = sorted({entry['academic_year'] for entry in entries}, reverse=True)
    selected_year = academic_year or (academic_years[0] if academic_years else '')
    filtered = [entry for entry in entries if not selected_year or entry['academic_year'] == selected_year]
    breakdown = year_breakdown(entries)
    trends = trends_payload(entries)
    return {
        'entries_count': len(entries),
        'selected_academic_year': selected_year,
        'academic_years': academic_years,
        'trend_cards': trends,
        'distribution': distribution_for(filtered)[:8],
        'year_over_year': breakdown[:3],
        'trend_series': trend_series(entries),
        'suggestions': suggestions_payload(entries, breakdown, trends),
        'recent_entries': entries[:8],
        'taxonomy': [{'label': item['label'], 'color': item['color']} for item in TECH_STACKS],
    }


def classify_payload(user, text):
    ensure_admin(user)
    entries = enrich_entries(source_entries())
    result = classify_text(text)
    return {
        **result,
        'pipeline': [
            {'label': 'Regex Validation', 'status': 'done'},
            {'label': 'TF-IDF Vectorization', 'status': 'done'},
            {'label': 'Naive Bayes Classification', 'status': 'done'},
            {'label': 'Curriculum Mapping', 'status': 'done'},
        ],
        'similar_projects': similar_projects(entries, result['matched_keywords']),
    }


def proposal_payload(user):
    payload = analytics_payload(user)
    trends = payload['trend_cards']
    suggestions = payload['suggestions']
    return {
        'title': 'Curriculum Analytics Proposal',
        'summary': (
            f'Analyzed {payload["entries_count"]} repository files. '
            f'Top technology signal is {trends["top_tech"]}; least represented is {trends["least_tech"]}.'
        ),
        'recommendations': [
            suggestion['body']
            for suggestion in suggestions
        ],
        'next_steps': [
            'Review course outcomes against the strongest technology signals.',
            'Use repository upload gaps to guide faculty reminders before the next defense cycle.',
            'Align rubric examples with emerging project domains found in the vault.',
        ],
    }


def analytics_entries_count():
    return len(source_entries())


def analytics_academic_year_count():
    return len({entry['academic_year'] for entry in source_entries() if entry.get('academic_year')})


def analytics_top_tech():
    entries = enrich_entries(source_entries())
    if not entries:
        return 'No data'
    return Counter(entry['tech_stack'] for entry in entries).most_common(1)[0][0]
