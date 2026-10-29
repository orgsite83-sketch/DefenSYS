"""
Automate Documenter Minutes of Defense Comments over HTTP REST API.

Simulates documenters recording realistic panelist comments for Capstone defense schedules
via the actual DefenSYS backend API endpoints:
  - Discovers schedules requiring minutes: stage.minutes_required=True or assigned documenter
  - Initializes / retrieves minutes draft: GET /api/defense/minutes/<schedule_id>/
  - Generates realistic, constructive panelist comments tailored by role (Chair, Technical, UI/UX)
  - Saves comments as draft: PATCH /api/defense/minutes/<schedule_id>/

By default, only missing draft comments are filled. Add --sign-all to submit as
the assigned documenter, accept/sign as the assigned adviser, then sign as the
administrator through the normal APIs. Existing uploaded signatures are used;
passwords and signature files are never changed. Partially signed records resume
at their next step; completed records are preserved. Dry runs never create drafts.

Usage Examples:
  # 1. Preview comments for all eligible schedules requiring minutes without saving:
  python execution/auto_documenter_minutes.py --all-minutes --dry-run

  # 2. Record comments for all schedules requiring minutes:
  python execution/auto_documenter_minutes.py --all-minutes

  # 3. Target a specific schedule by Schedule ID:
  python execution/auto_documenter_minutes.py --schedule-id 37

  # 4. Target a specific team by Team ID:
  python execution/auto_documenter_minutes.py --team-id 3

  # 5. Target a specific documenter username:
  python execution/auto_documenter_minutes.py --documenter 211

  # 6. Overwrite existing draft comments:
  python execution/auto_documenter_minutes.py --all-minutes --overwrite

  # 7. Preview/complete the current term's Project Proposal minutes:
  python execution/auto_documenter_minutes.py --all-minutes --stage "Project Proposal" --sign-all --admin admin --dry-run
"""

import argparse
import math
import os
import random
import sys
import time
from typing import Any, Dict, List, Optional
import requests

if __package__:
    from . import upload_deliverables as common
else:
    import upload_deliverables as common

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BACKEND_PATH = os.path.join(REPO_ROOT, "backend")
if BACKEND_PATH not in sys.path:
    sys.path.insert(0, BACKEND_PATH)

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass


def init_django():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "defensys_backend.settings")
    import django  # type: ignore
    django.setup()


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Automate recording defense minutes comments across teams and schedules."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="Base URL of DefenSYS backend (default: http://127.0.0.1:8000)",
    )
    parser.add_argument(
        "--all-minutes",
        action="store_true",
        help="Record comments for all Capstone schedules requiring minutes",
    )
    parser.add_argument(
        "--team-id",
        type=int,
        help="Filter by Team ID",
    )
    parser.add_argument(
        "--schedule-id",
        type=int,
        help="Filter by Defense Schedule ID",
    )
    parser.add_argument(
        "--documenter",
        type=str,
        help="Filter by documenter username (e.g. --documenter 211)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing panelist comments if already recorded in draft",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview comments and signatures without creating or changing records",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.1,
        help="Delay in seconds between requests (default: 0.1s)",
    )
    parser.add_argument('--stage', help='Only this Capstone stage label.')
    parser.add_argument('--semester-id', type=int, help='Academic term; defaults to the active semester.')
    parser.add_argument('--session-id', help='Only this scheduled session UUID.')
    parser.add_argument('--sign-all', action='store_true',
        help='Submit/sign as documenter, assigned adviser, then administrator using existing signatures.')
    parser.add_argument('--admin', help='Administrator username for the final signature; otherwise use the schedule creator or sole signed administrator.')
    parser.add_argument('--request-timeout', type=float, default=60,
        help='HTTP timeout in seconds (default: 60). Writes are never retried.')
    args = parser.parse_args(argv)
    if args.admin and not args.sign_all:
        parser.error('--admin requires --sign-all.')
    if not math.isfinite(args.delay) or not 0 <= args.delay <= 60:
        parser.error('--delay must be between 0 and 60 seconds.')
    if not math.isfinite(args.request_timeout) or not 0 < args.request_timeout <= 300:
        parser.error('--request-timeout must be greater than 0 and at most 300 seconds.')
    return args


# Realistic academic panel comments organized by panel role
CHAIR_FEEDBACK_POOL = [
    "Refine the project scope to clearly delineate core functional deliverables from optional extensions.",
    "Verify adherence to institutional research ethics and secure necessary data compliance approvals prior to deployment.",
    "Align the methodology milestones with the semester academic calendar to ensure deliverables are met on schedule.",
    "Clarify target beneficiary demographics and document direct stakeholder consultations in Chapter 1.",
    "Review the project risk assessment; outline concrete mitigation strategies for critical external dependencies.",
    "Ensure project objectives map directly to verifiable acceptance criteria in the evaluation chapter.",
]

TECHNICAL_FEEDBACK_POOL = [
    "Normalize database tables to at least 3NF and verify all foreign key constraints and cascade rules.",
    "Include complete Entity-Relationship Diagrams (ERD) with attribute data types in the technical appendix.",
    "Implement comprehensive exception handling and standard HTTP response status codes across all REST endpoints.",
    "Ensure sensitive configuration variables, API keys, and credentials remain isolated in environment configurations.",
    "Specify deployment infrastructure and document automated backup and recovery procedures for persisted data.",
    "Detail API endpoint caching and performance optimization strategies for concurrent user traffic.",
]

UI_UX_FEEDBACK_POOL = [
    "Conduct responsive layout validation across mobile and desktop viewports to maintain UI consistency.",
    "Follow WCAG accessibility guidelines, with particular focus on color contrast ratios and typographic hierarchy.",
    "Include high-fidelity wireframes and interactive state transitions in the design documentation.",
    "Standardize input validation feedback in frontend forms to provide descriptive user guidance on error states.",
    "Incorporate formal usability evaluation metrics (such as the System Usability Scale) for user acceptance testing.",
    "Streamline navigation workflows to reduce unnecessary clicks between dashboard and operational views.",
]

GENERAL_FEEDBACK_POOL = [
    "Provide comprehensive unit and integration test suites covering critical user flows.",
    "Document API schema specifications using standard OpenAPI / Swagger definitions for integration clarity.",
    "Strengthen the literature review by citing recent empirical research from peer-reviewed journals within the past 5 years.",
    "Elaborate on data collection instruments and verify questionnaire construct validity prior to administration.",
]


def generate_panelist_comment(role_snapshot: str, display_order: int) -> str:
    """Generates realistic, natural defense minutes feedback based on panel role."""
    role_lower = (role_snapshot or "").lower()

    if "chair" in role_lower:
        primary = random.choice(CHAIR_FEEDBACK_POOL)
        secondary = random.choice(GENERAL_FEEDBACK_POOL)
    elif display_order == 0 or "member 1" in role_lower:
        primary = random.choice(TECHNICAL_FEEDBACK_POOL)
        secondary = random.choice(GENERAL_FEEDBACK_POOL)
    elif "member 2" in role_lower or display_order == 1:
        primary = random.choice(UI_UX_FEEDBACK_POOL)
        secondary = random.choice(TECHNICAL_FEEDBACK_POOL)
    else:
        primary = random.choice(GENERAL_FEEDBACK_POOL)
        secondary = random.choice(UI_UX_FEEDBACK_POOL)

    # Avoid duplicate sentences
    if primary == secondary:
        return primary
    return f"{primary} {secondary}"


class MinutesAutomationError(ValueError):
    def __init__(self, detail, *, fatal=False):
        self.fatal = fatal
        super().__init__(detail)


def get_jwt_token_for_user(username: str) -> Optional[str]:
    """Normal short-lived access token without refresh-token or credential writes."""
    with common.local_read_only():
        from django.contrib.auth import get_user_model
        from rest_framework_simplejwt.tokens import AccessToken
        user = get_user_model().objects.filter(
            username=username, is_active=True, role__in=['faculty', 'admin']).first()
        return str(AccessToken.for_user(user)) if user else None


def fetch_eligible_schedules(team_id=None, schedule_id=None, documenter_username=None,
                             semester_id=None, stage=None, session_id=None):
    with common.local_read_only():
        from academic_period_management.services import active_semester
        from defense.scheduler.models import DefenseSchedule
        from django.db.models import F
        if semester_id is None:
            semester = active_semester()
            if semester is None:
                raise MinutesAutomationError('No active semester. Specify --semester-id.')
            semester_id = semester.pk
        qs = DefenseSchedule.objects.filter(scope='capstone', semester_id=semester_id,
            project_version=F('team__project_version'),
            status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE])
        if schedule_id:
            qs = qs.filter(pk=schedule_id)
        if team_id:
            qs = qs.filter(team_id=team_id)
        if documenter_username:
            qs = qs.filter(documenter__username=documenter_username)
        if stage:
            qs = qs.filter(defense_stage__label__iexact=stage.strip())
        if session_id:
            qs = qs.filter(session_id=session_id)
        return [{'id': schedule.pk, 'team_name': schedule.team.name,
                 'stage_label': schedule.stage_label}
                for schedule in qs.select_related('team', 'defense_stage').order_by(
                    'scheduled_date', 'start_time', 'pk')
                if schedule.requires_minutes or schedule.documenter_id]


def minutes_context(schedule_id, admin_username=None):
    """Read-only plan, including unsaved missing comment slots for a true dry run."""
    with common.local_read_only():
        from django.contrib.auth import get_user_model
        from django.db.models import Q
        from django.utils import timezone
        from defense.scheduler.models import DefenseSchedule
        from defense.minutes.models import DefenseMinutes
        from defense.minutes.services import missing_panelist_comments, minutes_panel_roster
        schedule = DefenseSchedule.objects.select_related(
            'team__adviser', 'semester', 'documenter', 'created_by').get(pk=schedule_id)
        minutes = DefenseMinutes.objects.filter(schedule=schedule).first()
        status = minutes.status if minutes else 'draft'
        comments = list(minutes.current_panelist_comments) if minutes else []
        if status == 'draft':
            comments.extend(missing_panelist_comments(minutes or DefenseMinutes(schedule=schedule), comments))
        admin_users = get_user_model().objects.filter(is_active=True).filter(Q(role='admin') | Q(is_superuser=True))
        if admin_username:
            admin = admin_users.filter(username=admin_username).first()
        elif schedule.created_by_id and admin_users.filter(pk=schedule.created_by_id).exists():
            admin = schedule.created_by
        else:
            candidates = list(admin_users.exclude(e_signature='').exclude(e_signature__isnull=True)[:2])
            admin = candidates[0] if len(candidates) == 1 else None
        signers = {'documenter': schedule.documenter, 'adviser': schedule.team.adviser, 'admin': admin}
        reasons = []
        if (schedule.scope != 'capstone' or schedule.status not in ('scheduled', 'done')
                or schedule.operation_state != 'normal'):
            reasons.append('The current defense is not available for minutes processing.')
        if (not schedule.semester.is_active or schedule.semester_id != schedule.team.semester_id
                or schedule.project_version != schedule.team.project_version):
            reasons.append('This assessment is outside the active team term/project.')
        if schedule.scheduled_date > timezone.localdate():
            reasons.append('The defense date is still in the future.')
        if not minutes_panel_roster(schedule):
            reasons.append('No panel roster is assigned.')
        if not schedule.documenter or not schedule.documenter.is_active:
            reasons.append('No active documenter is assigned.')
        signer_problems = []
        actors = {}
        for role, user in signers.items():
            actors[role] = {'id': user.pk if user else None, 'username': user.username if user else None}
            if not user or not user.is_active or user.role not in ('faculty', 'admin'):
                signer_problems.append(f'No active {role} account is available. Select the administrator with --admin when needed.')
            elif not user.e_signature or not user.e_signature.storage.exists(user.e_signature.name):
                signer_problems.append(f'{role.title()} {user.username} has no available uploaded signature.')
        if minutes:
            for role, field in [('documenter', 'documenter'), ('adviser', 'adviser')]:
                signed_by = getattr(minutes, f'{field}_signed_by_id')
                if signed_by and signed_by != actors[role]['id']:
                    signer_problems.append(f'The assigned {role} differs from the recorded signer; review this record in the app.')
        return {'schedule_id': schedule.pk, 'status': status,
            'pdf_file': bool(minutes and minutes.pdf_file),
            'comments': [{'id': c.pk, 'panelist': c.panelist_id,
                'guest': c.guest_invitation_id, 'role': c.panelist_role_snapshot,
                'order': c.display_order, 'comments': c.comments} for c in comments],
            'actors': actors, 'reasons': reasons, 'signer_problems': signer_problems,
            'stamp': (schedule.team_id, schedule.semester_id, schedule.project_version,
                schedule.team.project_version, schedule.revision, schedule.documenter_id,
                schedule.team.adviser_id, actors['admin']['id'],
                tuple((row['panelist_id'], row['guest_invitation_id']) for row in minutes_panel_roster(schedule)))}


class MinutesClient:
    """Every write uses the real actor's ordinary API; no automatic write retries."""
    def __init__(self, base_url, timeout):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.sessions = {}

    def request(self, method, schedule_id, username, *, action='', payload=None, pdf=False):
        if username not in self.sessions:
            token = get_jwt_token_for_user(username)
            if not token:
                raise MinutesAutomationError(f'Cannot authenticate {username}.', fatal=True)
            session = requests.Session()
            session.headers.update({'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
            self.sessions[username] = session
        url = f'{self.base_url}/api/defense/minutes/{schedule_id}/' + (f'{action}/' if action else '')
        try:
            response = self.sessions[username].request(method, url, json=payload,
                timeout=self.timeout, allow_redirects=False)
        except requests.RequestException as exc:
            raise MinutesAutomationError(
                f'{method} {action or "detail"} failed: {exc}. Check saved state before rerunning; writes are never retried.',
                fatal=True) from exc
        if response.status_code != 200:
            raise MinutesAutomationError(
                f'{method} {action or "detail"}: HTTP {response.status_code}: {response.text[:500]}',
                fatal=response.status_code in (401, 429))
        if pdf:
            if not response.content.startswith(b'%PDF-'):
                raise MinutesAutomationError('The PDF endpoint did not return a valid PDF.')
            return response.content
        try:
            data = response.json()
        except ValueError as exc:
            raise MinutesAutomationError('The minutes API did not return JSON.') from exc
        if not isinstance(data, dict):
            raise MinutesAutomationError('The minutes API returned an invalid response.')
        return data

    def close(self):
        for session in self.sessions.values():
            session.close()


def process_schedule(schedule_id, args, client):
    context = minutes_context(schedule_id, args.admin)
    original_stamp = context['stamp']
    result = {'comments': 0, 'signatures': 0, 'completed': 0, 'preserved': 0}
    if context['status'] == 'completed':
        if not context['pdf_file']:
            raise MinutesAutomationError('Completed minutes have no stored PDF. Review the record in the app.')
        print('  [KEEP] Minutes are already finalized.')
        result['preserved'] = 1
        return result
    problems = context['reasons'] + (context['signer_problems'] if args.sign_all else [])
    if problems:
        raise MinutesAutomationError(' '.join(problems))
    if args.dry_run:
        if context['status'] == 'draft':
            result['comments'] = sum(bool(args.overwrite or not c['comments'].strip()) for c in context['comments'])
            print(f"  [DRY-RUN] Would fill {result['comments']} missing/draft panel comments.")
        if args.sign_all:
            steps = {'draft': ['documenter', 'adviser', 'admin'],
                     'submitted': ['adviser', 'admin'], 'adviser_signed': ['admin']}.get(context['status'])
            if steps is None:
                raise MinutesAutomationError('Unknown minutes status.')
            for role in steps:
                print(f"  [DRY-RUN] Would accept/sign as {role}: {context['actors'][role]['username']}.")
            result['signatures'] = len(steps)
            result['completed'] = 1
        return result
    if context['status'] == 'draft':
        documenter = context['actors']['documenter']['username']
        # The ordinary detail endpoint initializes/synchronizes draft slots only in live mode.
        data = client.request('GET', schedule_id, documenter)
        fresh = minutes_context(schedule_id, args.admin)
        if fresh['stamp'] != context['stamp'] or fresh['status'] != 'draft':
            raise MinutesAutomationError('The assignment or minutes status changed. Refresh and rerun.')
        updates = [{'id': c['id'], 'comments': generate_panelist_comment(
            c.get('panelist_role_snapshot', ''), c.get('display_order', 0))}
            for c in data.get('panelist_comments', [])
            if args.overwrite or not (c.get('comments') or '').strip()]
        if updates:
            client.request('PATCH', schedule_id, documenter, payload={'comments': updates})
            result['comments'] = len(updates)
            print(f'  [OK] Saved {len(updates)} panelist comments.')
        else:
            print('  [KEEP] Existing draft comments preserved.')
    if not args.sign_all:
        return result
    context = minutes_context(schedule_id, args.admin)
    if any(not c['comments'].strip() for c in context['comments']):
        raise MinutesAutomationError('Every current panelist needs a comment before signing.')
    if context['stamp'] != original_stamp:
        raise MinutesAutomationError('The assignment changed while saving comments. Refresh and rerun.')
    reviewed_comments = [(c['panelist'], c['guest'], c['comments']) for c in context['comments']]
    for before, action, role, after in [
        ('draft', 'submit', 'documenter', 'submitted'),
        ('submitted', 'sign-adviser', 'adviser', 'adviser_signed'),
        ('adviser_signed', 'sign-chairman', 'admin', 'completed'),
    ]:
        if context['status'] != before:
            continue
        username = context['actors'][role]['username']
        client.request('GET', schedule_id, username, action='preview', pdf=True)
        fresh = minutes_context(schedule_id, args.admin)
        if (fresh['stamp'] != context['stamp'] or fresh['status'] != before
                or fresh['reasons'] or fresh['signer_problems']
                or [(c['panelist'], c['guest'], c['comments']) for c in fresh['comments']] != reviewed_comments):
            raise MinutesAutomationError('The reviewed minutes or assignment changed. Refresh and rerun.')
        data = client.request('POST', schedule_id, username, action=action, payload={})
        if data.get('status') != after:
            raise MinutesAutomationError(f'The signing response did not confirm {after}. Check saved state.')
        result['signatures'] += 1
        print(f'  [OK] Accepted/signed as {role}: {username}.')
        context = minutes_context(schedule_id, args.admin)
    if context['status'] == 'completed' and context['pdf_file']:
        client.request('GET', schedule_id, context['actors']['admin']['username'], action='pdf', pdf=True)
        result['completed'] = 1
        print('  [OK] Finalized minutes PDF verified.')
    else:
        raise MinutesAutomationError('Minutes have not reached completed status with an official PDF.')
    return result


def run(argv=None):
    args = parse_args(argv)
    args.base_url = common.server_url(args.base_url)
    if not (args.all_minutes or args.team_id or args.schedule_id or args.documenter):
        raise MinutesAutomationError('Specify --all-minutes, --team-id, --schedule-id, or --documenter.')
    schedules = fetch_eligible_schedules(args.team_id, args.schedule_id, args.documenter,
        args.semester_id, args.stage, args.session_id)
    print(f'DefenSYS minutes automation: {len(schedules)} schedules; '
          f'{"DRY RUN" if args.dry_run else "LIVE"}; '
          f'{"comments and all signatures" if args.sign_all else "draft comments only"}.')
    totals = {'comments': 0, 'signatures': 0, 'completed': 0, 'preserved': 0}
    failed = 0
    client = MinutesClient(args.base_url, args.request_timeout)
    try:
        for schedule in schedules:
            print(f"\n[*] Schedule #{schedule['id']} | {schedule['team_name']} ({schedule['stage_label']})")
            try:
                result = process_schedule(schedule['id'], args, client)
                for key in totals:
                    totals[key] += result[key]
            except MinutesAutomationError as exc:
                print(f'[FAIL] {exc}')
                failed += 1
                if exc.fatal:
                    break
            if args.delay:
                time.sleep(args.delay)
    finally:
        client.close()
    print(f'\nSUMMARY: {totals}; failed={failed}; selected={len(schedules)}')
    if args.dry_run:
        print('Preview only. No drafts, comments, signatures or PDFs were stored.')
    return 1 if failed else 0


if __name__ == '__main__':
    try:
        sys.exit(run())
    except (MinutesAutomationError, common.UploadError) as exc:
        print(f'[FAIL] {exc}')
        sys.exit(1)
