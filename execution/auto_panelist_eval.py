"""
Automate Panelist Grading and Defense Verdicts over HTTP REST API.

Simulates faculty and assigned external panelists submitting evaluations via the actual
DefenSYS backend API endpoints:
  - Fetches assignments: GET /api/defense/schedules/panelist-assignments/
  - Generates criteria scores (default: 7 to 9 out of 10)
  - Submits evaluations: POST /api/defense/schedules/submit-grades/
  - External invitations use guest-assignments/ and guest-submit-grades/ with guest JWTs
  - Requests allowed Capstone defense verdicts as the assigned chair: PATCH /api/defense/schedules/<schedule_id>/verdict/
    (Note: PIT events do not use verdicts and are scored only)

Usage Examples:
  # 1. Run for all assigned panelists in the active semester:
  python execution/auto_panelist_eval.py --all-panelists --min-score 7 --max-score 9

  # 2. Dry-run first to preview evaluations and verdicts without saving:
  python execution/auto_panelist_eval.py --all-panelists --dry-run

  # 3. Target a specific team by Team ID:
  python execution/auto_panelist_eval.py --team-id 3 --min-score 7 --max-score 9

  # 4. Filter by defense stage, session UUID, or academic term:
  python execution/auto_panelist_eval.py --all-panelists --stage "Project Proposal" --session-id <uuid>

  # 5. Only evaluate first-year PIT events (scores only, no verdicts):
  python execution/auto_panelist_eval.py --all-panelists --scope pit --year 1

  # 6. Request a permitted Capstone outcome (default: auto, following the API):
  python execution/auto_panelist_eval.py --all-panelists --scope capstone --verdict approved_with_revisions

  # 7. Issue verdicts only for Capstone defenses whose panel scores are already posted:
  python execution/auto_panelist_eval.py --all-panelists --verdict-only

  # 8. Fill only missing external evaluations for one PIT event:
  python execution/auto_panelist_eval.py --external-only --scope pit --stage "PIT System Prototype Showcase" --dry-run

Exit codes: 0 = completed, 1 = failed request/configuration, 2 = unavailable evaluations or pending verdicts.
Dry runs use GET requests only and do not create refresh-token records.
"""

import argparse
from datetime import date, datetime, timedelta
from functools import wraps
import math
import os
import random
import sys
import time
from typing import Any, Dict, List, Optional
import requests
from zoneinfo import ZoneInfo

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


def read_only_lookup(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        with common.local_read_only():
            return function(*args, **kwargs)
    return wrapped


DEFAULT_VERDICT_REMARKS = {
    "approved": "Approved by panel deliberation. Proceed to final manuscript submission.",
    "approved_with_revisions": "Approved with revisions. Comply with all panel recommendations by deadline.",
    "for_redefense": "For re-defense. Re-defense required following revision of methodology and prototypes.",
    "failed": "Failed to meet minimum defense requirements.",
    "project_rejected": "Project concept and implementation rejected.",
}


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Automate defense schedule panel evaluations across teams using random scores and record Capstone verdicts."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="Base URL of DefenSYS backend (default: http://127.0.0.1:8000)",
    )
    parser.add_argument(
        "--all-panelists",
        action="store_true",
        help="Evaluate all assigned faculty and external panelists in the active semester",
    )
    parser.add_argument(
        "--panelists",
        nargs="+",
        help="Only these faculty/admin usernames (e.g. --panelists 208 215)",
    )
    external = parser.add_mutually_exclusive_group()
    external.add_argument("--external-only", action="store_true", help="Only evaluate assigned external invitations")
    external.add_argument("--exclude-external", action="store_true", help="Explicitly skip external invitations")
    parser.add_argument(
        "--team-id",
        type=int,
        help="Filter evaluations to a specific Team ID",
    )
    parser.add_argument(
        "--stage",
        help="Only evaluate this Capstone stage label or PIT event name",
    )
    parser.add_argument(
        "--session-id",
        help="Only evaluate defenses in this scheduled session UUID",
    )
    parser.add_argument(
        "--semester-id",
        type=int,
        help="Only evaluate defenses in this academic semester ID",
    )
    parser.add_argument(
        "--scope",
        choices=["capstone", "pit"],
        help="Filter evaluations by defense scope ('capstone' or 'pit')",
    )
    parser.add_argument('--year', type=common.year_label, help='Filter the cohort, e.g. --year 1.')
    parser.add_argument('--include-drafts', action='store_true',
        help='Preserve saved draft scores/remarks, fill missing scores, then submit. Drafts are skipped by default.')
    parser.add_argument(
        "--min-score",
        type=float,
        default=7.0,
        help="Minimum criterion score (default: 7.0)",
    )
    parser.add_argument(
        "--max-score",
        type=float,
        default=9.0,
        help="Maximum criterion score (default: 9.0)",
    )
    parser.add_argument(
        "--verdict",
        default="auto",
        choices=["auto", "approved", "approved_with_revisions", "for_redefense", "failed", "project_rejected"],
        help="Follow the API's allowed outcome (default: auto); explicit choices must be permitted by the API.",
    )
    parser.add_argument(
        "--verdict-remarks",
        help="Custom remarks to record with the Capstone verdict (defaults based on verdict)",
    )
    parser.add_argument(
        "--revision-deadline",
        help="Revision deadline (YYYY-MM-DD) for 'approved_with_revisions' (default: 14 days from today)",
    )
    parser.add_argument(
        "--redefense-verification",
        action="store_true",
        help="Flag indicating verification required before redefense (for 'for_redefense')",
    )
    parser.add_argument(
        "--no-verdict",
        action="store_true",
        help="Skip recording defense verdicts for Capstone defenses",
    )
    parser.add_argument(
        "--verdict-only",
        action="store_true",
        help="Only record verdicts for Capstone defenses that already have complete panel evaluations",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be evaluated without submitting to the API",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.1,
        help="Delay in seconds between requests (default: 0.1s)",
    )
    args = parser.parse_args(argv)
    if not (math.isfinite(args.min_score) and math.isfinite(args.max_score)
            and 0 <= args.min_score <= args.max_score <= 10):
        parser.error("Scores must satisfy 0 <= --min-score <= --max-score <= 10 (scaled to each criterion maximum).")
    if not math.isfinite(args.delay) or not 0 <= args.delay <= 60:
        parser.error("--delay must be a finite number between 0 and 60 seconds.")
    if args.external_only and args.panelists:
        parser.error("--external-only cannot be combined with --panelists.")
    if args.verdict_only and args.no_verdict:
        parser.error("--verdict-only cannot be combined with --no-verdict.")
    if args.revision_deadline:
        try:
            date.fromisoformat(args.revision_deadline)
        except ValueError:
            parser.error("--revision-deadline must be YYYY-MM-DD.")
    return args


def fetch_target_schedule_ids(team_id=None, stage=None, session_id=None, semester_id=None, scope=None, year=None):
    """One authoritative allowlist for discovery and every API assignment response."""
    with common.local_read_only():
        from django.db.models import Q, F
        from defense.scheduler.models import DefenseSchedule
        from academic_period_management.services import active_semester
        qs = DefenseSchedule.objects.filter(status=DefenseSchedule.STATUS_SCHEDULED,
                                            project_version=F('team__project_version'))
        if team_id:
            qs = qs.filter(team_id=team_id)
        if stage:
            qs = qs.filter(Q(defense_stage__label__iexact=stage.strip()) | Q(scope='pit', event_name__iexact=stage.strip()))
        if session_id:
            qs = qs.filter(session_id=session_id.strip())
        if semester_id:
            qs = qs.filter(semester_id=semester_id)
        elif not team_id and not session_id:
            semester = active_semester()
            if semester is None:
                raise ValueError("No active semester. Specify --semester-id, --team-id, or --session-id.")
            qs = qs.filter(semester=semester)
        if scope:
            qs = qs.filter(scope=scope)
        if year:
            qs = qs.filter(team__year_level=year)
        return list(qs.order_by('pk').values_list('pk', flat=True))


def fetch_panelist_users(
    specific_usernames: Optional[List[str]] = None,
    team_id: Optional[int] = None,
    stage: Optional[str] = None,
    session_id: Optional[str] = None,
    semester_id: Optional[int] = None,
    scope: Optional[str] = None,
    schedule_ids: Optional[List[int]] = None,
) -> List[str]:
    if schedule_ids is None:
        schedule_ids = fetch_target_schedule_ids(team_id, stage, session_id, semester_id, scope)
    with common.local_read_only():
        from django.contrib.auth import get_user_model
        from defense.scheduler.models import SchedulePanelist
        users = get_user_model().objects.filter(is_active=True, role__in=['faculty', 'admin'],
            pk__in=SchedulePanelist.objects.filter(schedule_id__in=schedule_ids).values('panelist_id'))
        if specific_usernames:
            users = users.filter(username__in=specific_usernames)
        return list(users.order_by('username').values_list('username', flat=True))


@read_only_lookup
def fetch_external_panelists(schedule_ids):
    """Include legacy single-defense invitations and current multi-defense invitations."""
    init_django()
    from django.db.models import Q
    from django.utils import timezone
    from user_management.models import GuestPanelistCode, ExternalEvaluator
    from user_management.external_evaluators import invitation_schedule_ids

    invitations = GuestPanelistCode.objects.filter(
        Q(schedules__pk__in=schedule_ids) | Q(defense_schedule_id__in=schedule_ids)
    ).select_related('evaluator').prefetch_related('schedules').distinct().order_by('pk')
    result = []
    for invitation in invitations:
        if not set(invitation_schedule_ids(invitation)).intersection(schedule_ids):
            continue
        reason = ''
        if not invitation.is_active:
            reason = 'Invitation revoked; renew access in External Evaluators.'
        elif invitation.evaluator_id and (not invitation.evaluator.is_active or invitation.evaluator.status != ExternalEvaluator.APPROVED):
            reason = 'External evaluator is inactive or not approved.'
        elif invitation.expires_at and invitation.expires_at <= timezone.now():
            reason = 'Invitation expired; renew access in External Evaluators.'
        result.append({'id': invitation.pk, 'name': invitation.guest_name, 'unavailable_reason': reason})
    return result


@read_only_lookup
def get_guest_jwt_token(invitation_id):
    """Mint the normal scoped guest token without exchanging codes or updating access records."""
    init_django()
    from authentication_access_control.guest_tokens import create_guest_access_token
    from user_management.external_evaluators import invitation_is_available
    from user_management.models import GuestPanelistCode
    invitation = GuestPanelistCode.objects.select_related('evaluator', 'defense_schedule__team').get(pk=invitation_id)
    if not invitation_is_available(invitation):
        return None
    return create_guest_access_token(invitation)


def generate_scores(criteria, minimum, maximum):
    """Treat the CLI range as a ten-point scale, including zero and fractional maxima."""
    scores = []
    for criterion in criteria:
        maximum_score = float(criterion.get('max_score', 10))
        if not math.isfinite(maximum_score) or maximum_score < 0:
            raise ValueError('The assigned rubric contains an invalid criterion maximum.')
        score = min(maximum_score, max(0, round(random.uniform(minimum, maximum) / 10 * maximum_score, 2)))
        scores.append({'criterion_id': criterion['id'], 'score': score})
    return scores


def build_submissions(assignment, minimum, maximum, remarks, *, include_drafts=False):
    rubric = assignment.get('panel_rubric') or {}
    criteria = rubric.get('criteria') or []
    target = rubric.get('target_type')
    members = assignment.get('members') or []
    if not isinstance(criteria, list) or not criteria:
        raise ValueError('No panel rubric criteria are configured.')
    if target not in ('team', 'individual', 'both'):
        raise ValueError('The assigned rubric has an unsupported grading target.')
    if len({c['id'] for c in criteria}) != len(criteria):
        raise ValueError('The assigned rubric has duplicate criterion IDs.')
    if target in ('individual', 'both') and (not members or len({m['id'] for m in members}) != len(members)):
        raise ValueError('A complete, unique team membership is required for individual grading.')
    draft = assignment.get('draft')
    if draft and not include_drafts:
        raise ValueError('A saved evaluation draft exists. Finish it in the app or use --include-drafts to preserve and complete it.')
    groups = []
    if target == 'team':
        groups = [(None, criteria)]
    elif target == 'individual':
        groups = [(member['id'], criteria) for member in members]
    else:
        if any(c.get('target_type', 'team') not in ('team', 'individual') for c in criteria):
            raise ValueError('The assigned mixed rubric contains an unsupported criterion target.')
        team_criteria = [c for c in criteria if c.get('target_type', 'team') == 'team']
        individual_criteria = [c for c in criteria if c.get('target_type', 'team') == 'individual']
        if team_criteria:
            groups.append((None, team_criteria))
        if individual_criteria:
            groups.extend((member['id'], individual_criteria) for member in members)
    concepts = assignment.get('assessment_concepts') or []
    per_concept = (assignment.get('assessment_policy') or {}).get('per_concept', bool(concepts))
    keys = [concept['key'] for concept in concepts] if per_concept else ['']
    if not keys or len(set(keys)) != len(keys) or (per_concept and any(not isinstance(key, str) or not key for key in keys)):
        raise ValueError('The hearing has no complete, unique set of assessed concepts. Refresh its configuration.')
    rows = {}
    allowed = {}
    for key in keys:
        for student_id, selected in groups:
            identity = (key, student_id)
            rows[identity] = {'student_id': student_id, 'criteria_scores': generate_scores(selected, minimum, maximum), 'remarks': remarks}
            allowed[identity] = {criterion['id']: float(criterion.get('max_score', 10)) for criterion in selected}
            if key:
                rows[identity]['concept_key'] = key
    if not rows:
        raise ValueError('No complete grading targets are available for this rubric.')
    seen = set()
    for saved in (draft or {}).get('submissions', []):
        identity = (saved.get('concept_key', ''), saved.get('student_id'))
        if identity not in rows or identity in seen:
            raise ValueError('The saved draft no longer matches the hearing targets.')
        seen.add(identity)
        scores = {}
        for item in saved.get('criteria_scores', []):
            criterion_id = item.get('criterion_id', item.get('id'))
            score = float(item.get('score'))
            if (criterion_id not in allowed[identity] or criterion_id in scores or not math.isfinite(score)
                    or not 0 <= score <= allowed[identity][criterion_id]):
                raise ValueError('The saved draft contains an invalid or outdated criterion score.')
            scores[criterion_id] = score
        for item in rows[identity]['criteria_scores']:
            if item['criterion_id'] in scores:
                item['score'] = scores[item['criterion_id']]
        if 'remarks' in saved:
            if not isinstance(saved['remarks'], str):
                raise ValueError('The saved draft remarks must be text.')
            rows[identity]['remarks'] = saved['remarks']
    return list(rows.values())


class AssignmentError(ValueError):
    def __init__(self, code, detail):
        self.code = code
        super().__init__(detail)


def current_assignment(session, url, schedule_id):
    response = session.get(url, timeout=10, allow_redirects=False)
    if response.status_code != 200:
        raise AssignmentError(response.status_code, f'Assignment refresh failed (HTTP {response.status_code}).')
    data = response.json()
    if not isinstance(data, dict) or not isinstance(data.get('teams'), list):
        raise ValueError('The assignment API returned an invalid response.')
    rows = [row for row in data['teams'] if isinstance(row, dict) and row.get('schedule_id') == schedule_id]
    if len(rows) != 1:
        raise ValueError('The current schedule is no longer available to this panelist.')
    return rows[0]


def assignment_matches(row, args, allowed):
    return (row.get('schedule_id') in allowed
            and (not args.team_id or (row.get('id') or row.get('team_id')) == args.team_id)
            and (not args.stage or str(row.get('defense_stage', '')).strip().casefold() == args.stage.strip().casefold())
            and (not args.session_id or str(row.get('session_id', '')) == str(args.session_id))
            and (not args.semester_id or row.get('semester_id') == args.semester_id)
            and (not args.scope or (row.get('scope') or ('capstone' if row.get('is_capstone') else 'pit')) == args.scope)
            and (not getattr(args, 'year', None) or row.get('year_level') == args.year))


def requires_concept_decision(row):
    workflow = (row.get('grade_record') or {}).get('workflow') or {}
    return bool(row.get('assessment_concepts') or (row.get('assessment_policy') or {}).get('per_concept')
                or workflow.get('concept_workflow'))


def plan_verdict(row, requested):
    """Use the chair's current API facts, never the academic weighted score."""
    if row.get('verdict'):
        return 'existing', f'Existing verdict: {row["verdict"]}.', None
    if requires_concept_decision(row):
        return 'manual', 'Concept assessments saved; the chair must select a qualifying concept and record the outcome.', None
    if row.get('is_chair') is not True or row.get('can_issue_verdict') is not True:
        return 'pending', row.get('verdict_unavailable_reason') or 'The assigned chair is not currently allowed to issue a verdict.', None
    workflow = (row.get('grade_record') or {}).get('workflow') or {}
    rule = workflow.get('outcome_rule')
    if (row.get('assessment_policy') or {}).get('version') == 1 and not rule:
        return 'pending', 'The current configured outcome assessment is unavailable.', None
    if rule is not None:
        allowed = rule.get('allowed_verdicts') or []
        if not rule.get('panel_complete') or not allowed:
            return 'pending', rule.get('reason') or 'Every required faculty and external evaluation must be complete.', None
        verdict = ('approved' if 'approved' in allowed else 'for_redefense' if allowed == ['for_redefense'] else None) if requested == 'auto' else requested
        if verdict not in allowed:
            return 'pending', f'Requested verdict is not permitted by the panel qualification rule. Allowed: {", ".join(allowed)}.', None
    else:
        verdict = 'approved' if requested == 'auto' else requested
    return 'ready', '', verdict


@read_only_lookup
def get_jwt_token_for_user(username: str) -> Optional[str]:
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    from rest_framework_simplejwt.tokens import AccessToken  # type: ignore

    User = get_user_model()
    try:
        user = User.objects.get(username=username, is_active=True, role__in=['faculty', 'admin'])
        # A short-lived access token does not insert an OutstandingToken row in dry runs.
        return str(AccessToken.for_user(user))
    except Exception as e:
        print(f"  [FAIL] Failed to generate token for {username}: {e}")
        return None


@read_only_lookup
def get_schedule_chair_username(schedule_id: int) -> Optional[str]:
    init_django()
    from defense.scheduler.models import SchedulePanelist  # type: ignore
    chairs = list(
        SchedulePanelist.objects.filter(schedule_id=schedule_id, is_chair=True, panelist__is_active=True)
        .values_list('panelist__username', flat=True)
    )
    return chairs[0] if len(chairs) == 1 else None


def submit_schedule_verdict(
    base_url: str,
    schedule_id: int,
    verdict: str,
    remarks: str,
    revision_deadline: Optional[str] = None,
    redefense_verification: bool = False,
    actor_username: Optional[str] = None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    if dry_run:
        return {"status": "dry_run"}

    if not actor_username:
        return {"status": "error", "detail": "No active assigned panel chair available."}
    if get_schedule_chair_username(schedule_id) != actor_username:
        return {"status": "error", "detail": "The assigned chair changed; refresh the assignments before requesting a verdict."}

    token = get_jwt_token_for_user(actor_username)
    if not token:
        return {"status": "error", "detail": f"Failed to acquire token for actor {actor_username}."}

    payload = {
        "verdict": verdict,
        "verdict_remarks": remarks,
        "redefense_verification_required": redefense_verification,
    }
    if verdict == "approved_with_revisions":
        if not revision_deadline:
            revision_deadline = (datetime.now(ZoneInfo('Asia/Manila')).date() + timedelta(days=14)).isoformat()
        payload["revision_deadline"] = revision_deadline

    url = f"{base_url.rstrip('/')}/api/defense/schedules/{schedule_id}/verdict/"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    try:
        resp = requests.patch(url, json=payload, headers=headers, timeout=10, allow_redirects=False)
        if resp.status_code in (200, 201):
            return {"status": "ok", "data": resp.json()}
        else:
            try:
                err_data = resp.json()
                detail = err_data.get("detail") or str(err_data)
            except Exception:
                detail = resp.text
            return {"status": "error", "code": resp.status_code, "detail": detail}
    except Exception as e:
        return {"status": "error", "detail": str(e)}


def run(argv=None):
    args = parse_args(argv)
    args.base_url = common.server_url(args.base_url)

    specific_panelists = None
    if args.panelists:
        specific_panelists = []
        for p in args.panelists:
            specific_panelists.extend([u.strip() for u in p.split(",") if u.strip()])

    if not args.all_panelists and not specific_panelists and not args.team_id and not args.session_id and not args.external_only:
        print("[!] Error: Specify --all-panelists, --external-only, --panelists <username...>, --team-id <id>, or --session-id <uuid>.")
        sys.exit(1)

    print("[*] Discovering assigned defense panelists...")
    schedule_ids = fetch_target_schedule_ids(args.team_id, args.stage, args.session_id, args.semester_id,
                                             args.scope, year=getattr(args, 'year', None))
    if not schedule_ids:
        print('[SKIP] No current scheduled defenses match the selected cohort/event/stage/term. Nothing was submitted.')
        return 0
    allowed_schedules = set(schedule_ids)
    panelist_usernames = [] if args.external_only else fetch_panelist_users(
        specific_usernames=specific_panelists,
        team_id=args.team_id,
        stage=args.stage,
        session_id=args.session_id,
        semester_id=args.semester_id,
        scope=args.scope,
        schedule_ids=schedule_ids,
    )
    external_panelists = [] if args.exclude_external or specific_panelists else fetch_external_panelists(schedule_ids)
    actors = [{'name': u, 'username': u, 'is_external': False} for u in panelist_usernames]
    actors.extend({**invitation, 'is_external': True} for invitation in external_panelists)
    if specific_panelists:
        missing = sorted(set(specific_panelists) - set(panelist_usernames))
        if missing:
            raise ValueError(f"No active, assigned faculty/admin panelist in the selected schedules: {', '.join(missing)}")
    if not actors:
        print('[PENDING] Matching defenses have no selected active panelist assignments. Check the panel roster.')
        return 2

    min_s = args.min_score
    max_s = args.max_score

    print("=" * 70)
    print("  DefenSYS Panelist Evaluation Automation")
    print("=" * 70)
    print(f"  Target Server   : {args.base_url}")
    print(f"  Total Panelists : {len(panelist_usernames)}")
    print(f"  External Invites: {len(external_panelists)}")
    print(f"  Score Range     : {min_s} to {max_s} out of 10 (scaled per criterion)")
    if args.scope:
        print(f"  Scope Filter    : {args.scope.upper()}")
    if getattr(args, 'year', None):
        print(f'  Year Filter     : {args.year}')
    if args.stage:
        print(f"  Stage Filter    : {args.stage}")
    if args.session_id:
        print(f"  Session UUID    : {args.session_id}")
    if args.semester_id:
        print(f"  Semester ID     : {args.semester_id}")
    if not args.no_verdict:
        print(f"  Capstone Verdict: {args.verdict.upper()} (assigned chair; subject to API readiness/outcome)")
    print(f"  Mode            : {'DRY RUN (No changes saved)' if args.dry_run else 'LIVE SUBMISSION'}")
    print("=" * 70)

    total_submitted = 0
    total_skipped = 0
    total_unavailable = 0
    total_failed = 0
    total_verdicts_issued = 0
    total_verdicts_skipped = 0
    total_verdicts_pending = 0

    # Track unique Capstone schedules encountered across all panelists for Verdict phase
    capstone_schedules: Dict[int, Dict[str, Any]] = {}
    concept_schedule_ids = set()
    abort_batch = False

    remarks_pool = [
        "Well-structured presentation and sound methodology.",
        "Demonstrated strong technical understanding and clear scope.",
        "Solid prototype progress. Feasibility and problem alignment are clear.",
        "Good defense performance. Recommendations noted for next phase.",
    ]

    for idx, actor in enumerate(actors, 1):
        if abort_batch:
            break
        is_external = actor['is_external']
        username = f"{actor['name']} (external invitation #{actor['id']})" if is_external else actor['username']
        reason = actor.get('unavailable_reason')
        if reason:
            print(f"  [UNAVAILABLE] {username}: {reason}")
            total_unavailable += 1
            continue
        token = get_guest_jwt_token(actor['id']) if is_external else get_jwt_token_for_user(username)
        if not token:
            print(f"  [FAIL] Could not authenticate {username}.")
            total_failed += 1
            continue

        session = requests.Session()
        session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

        assignment_endpoint = 'guest-assignments' if is_external else 'panelist-assignments'
        url = f"{args.base_url.rstrip('/')}/api/defense/schedules/{assignment_endpoint}/"
        try:
            resp = session.get(url, timeout=10, allow_redirects=False)
            if resp.status_code != 200:
                print(f"  [✗] Failed to fetch assignments for panelist {username} (HTTP {resp.status_code})")
                total_failed += 1
                abort_batch = resp.status_code in (401, 429)
                session.close()
                continue
            data = resp.json()
            if not isinstance(data, dict) or not isinstance(data.get('teams'), list):
                raise ValueError('The assignment API returned an invalid response.')
        except Exception as e:
            print(f"  [✗] Error connecting to API: {e}")
            total_failed += 1
            session.close()
            continue

        teams = data.get("teams", [])

        filtered_teams = [row for row in teams if assignment_matches(row, args, allowed_schedules)]

        print(f"\n[{idx}/{len(actors)}] Panelist: {username} (Matching Teams: {len(filtered_teams)})")

        for team_payload in filtered_teams:
            schedule_id = team_payload.get('schedule_id')
            if not args.dry_run and not args.verdict_only and not team_payload.get('is_posted'):
                try:
                    team_payload = current_assignment(session, url, schedule_id)
                    if not assignment_matches(team_payload, args, allowed_schedules):
                        raise ValueError('The assignment moved outside the requested cohort or event/stage.')
                except (ValueError, requests.RequestException) as error:
                    print(f'  [FAIL] Schedule #{schedule_id}: {error}')
                    total_failed += 1
                    abort_batch = isinstance(error, AssignmentError) and error.code in (401, 429)
                    if abort_batch:
                        break
                    continue
            team_name = team_payload.get("name") or team_payload.get("team_name") or f"Team {team_payload.get('id')}"
            schedule_id = team_payload.get("schedule_id")
            if requires_concept_decision(team_payload):
                concept_schedule_ids.add(schedule_id)
            team_id = team_payload.get("id") or team_payload.get("team_id")
            is_posted = team_payload.get("is_posted", False)
            schedule_scope = team_payload.get("scope") or ("capstone" if team_payload.get("is_capstone") else "pit")
            is_capstone = schedule_scope == "capstone"

            if is_posted:
                print(f"  [-] {team_name} (Schedule #{schedule_id}) already graded by {username}. Skipping.")
                total_skipped += 1
                # If this team was already graded, track for Capstone verdict phase if needed
                if is_capstone and schedule_id:
                    capstone_schedules[schedule_id] = {
                        "team_name": team_name,
                        "team_id": team_id,
                        "schedule_id": schedule_id,
                        "verdict": team_payload.get("verdict"),
                    }
                continue

            if args.verdict_only:
                if is_capstone and schedule_id:
                    capstone_schedules[schedule_id] = {'team_name': team_name, 'team_id': team_id,
                                                      'schedule_id': schedule_id, 'verdict': team_payload.get('verdict')}
                continue

            # Check backend eligibility to avoid unwanted data or locked evaluation errors
            if team_payload.get("grading_available") is not True:
                reason = team_payload.get("grading_unavailable_reason") or "Grading is currently unavailable for this schedule."
                print(f"  [SKIP] {team_name} (Schedule #{schedule_id}): {reason}")
                total_unavailable += 1
                continue

            eval_context = team_payload.get("evaluation_context")
            if not isinstance(eval_context, str) or not eval_context:
                print(f'  [SKIP] {team_name}: The API did not supply a current evaluation context.')
                total_unavailable += 1
                continue
            remarks = random.choice(remarks_pool)
            try:
                submissions = build_submissions(team_payload, min_s, max_s, remarks,
                                                include_drafts=getattr(args, 'include_drafts', False))
            except (ValueError, TypeError, KeyError) as error:
                print(f'  [SKIP] {team_name}: {error}')
                total_unavailable += 1
                continue

            payload = {
                "team_id": team_id,
                "schedule_id": schedule_id,
                "evaluation_context": eval_context,
                "submissions": submissions,
            }

            if args.dry_run:
                print(f"    [DRY-RUN] Would submit panel grade for {team_name} (Schedule #{schedule_id}, {len(submissions)} submission items)")
                total_submitted += 1
                if is_capstone and schedule_id:
                    capstone_schedules[schedule_id] = {
                        "team_name": team_name,
                        "team_id": team_id,
                        "schedule_id": schedule_id,
                        "verdict": team_payload.get("verdict"),
                    }
            else:
                submit_endpoint = 'guest-submit-grades' if is_external else 'submit-grades'
                submit_url = f"{args.base_url.rstrip('/')}/api/defense/schedules/{submit_endpoint}/"
                try:
                    s_resp = session.post(submit_url, json=payload, timeout=10, allow_redirects=False)
                    if s_resp.status_code in (200, 201):
                        res_data = s_resp.json()
                        p_score = res_data.get("panel_score")
                        score_str = f"Score: {float(p_score):.2f}%" if p_score is not None else "Saved"
                        print(f"    [OK] {team_name}: Submitted successfully! ({score_str})")
                        total_submitted += 1
                        if is_capstone and schedule_id:
                            capstone_schedules[schedule_id] = {
                                "team_name": team_name,
                                "team_id": team_id,
                                "schedule_id": schedule_id,
                                "verdict": team_payload.get("verdict"),
                            }
                    else:
                        print(f"    [FAIL] Failed to submit for {team_name} (HTTP {s_resp.status_code}): {s_resp.text}")
                        total_failed += 1
                        abort_batch = s_resp.status_code in (401, 429)
                except Exception as e:
                    print(f"    [FAIL] Network error submitting for {team_name}: {e}")
                    total_failed += 1

            if abort_batch:
                break
            time.sleep(args.delay)
        session.close()

    # Phase 2: Capstone Defense Verdict Processing
    if not args.no_verdict and capstone_schedules and not abort_batch:
        print("\n" + "=" * 70)
        print("  Phase 2: Capstone Defense Verdict Processing")
        print("=" * 70)

        for sched_id, sched_info in sorted(capstone_schedules.items()):
            t_name = sched_info["team_name"]
            if sched_id in concept_schedule_ids:
                print(f'  [-] {t_name}: Concept hearing; the chair must review the concepts and record the outcome.')
                total_verdicts_skipped += 1
                continue
            existing_verdict = sched_info.get("verdict")

            if existing_verdict:
                print(f"  [-] {t_name} (Schedule #{sched_id}) already has verdict: \"{existing_verdict}\". Skipping.")
                total_verdicts_skipped += 1
                continue

            chair_user = get_schedule_chair_username(sched_id)
            if not chair_user:
                print(f"  [VERDICT PENDING] {t_name} (Schedule #{sched_id}): Assign one active panel chair; no admin fallback is used.")
                total_verdicts_pending += 1
                continue
            chair_session = requests.Session()
            try:
                chair_token = get_jwt_token_for_user(chair_user)
                if not chair_token:
                    raise ValueError('Unable to authenticate the assigned chair.')
                chair_session.headers.update({'Authorization': f'Bearer {chair_token}'})
                current = current_assignment(chair_session,
                    f'{args.base_url}/api/defense/schedules/panelist-assignments/', sched_id)
                if not assignment_matches(current, args, allowed_schedules):
                    raise ValueError('The current chair assignment moved outside the requested cohort or stage.')
                verdict_state, detail, verdict = plan_verdict(current, args.verdict)
            except (ValueError, requests.RequestException) as error:
                print(f'  [VERDICT PENDING] {t_name}: {error}')
                total_verdicts_pending += 1
                if isinstance(error, AssignmentError) and error.code in (401, 429):
                    total_failed += 1
                    abort_batch = True
                    break
                continue
            finally:
                chair_session.close()
            if verdict_state in ('existing', 'manual'):
                print(f'  [-] {t_name}: {detail}')
                total_verdicts_skipped += 1
                continue
            if verdict_state != 'ready':
                print(f'  [VERDICT PENDING] {t_name}: {detail}')
                total_verdicts_pending += 1
                continue
            verdict_remarks = args.verdict_remarks or DEFAULT_VERDICT_REMARKS.get(verdict, 'Evaluated by panel deliberation.')

            if args.dry_run:
                print(f"    [DRY-RUN] Would request verdict \"{verdict}\" for {t_name} (Schedule #{sched_id}) as {chair_user}.")
                total_verdicts_issued += 1
            else:
                res = submit_schedule_verdict(
                    base_url=args.base_url,
                    schedule_id=sched_id,
                    verdict=verdict,
                    remarks=verdict_remarks,
                    revision_deadline=args.revision_deadline,
                    redefense_verification=args.redefense_verification,
                    actor_username=chair_user,
                    dry_run=args.dry_run,
                )
                if res.get("status") == "ok":
                    print(f"    [VERDICT OK] {t_name} (Schedule #{sched_id}): Defense verdict \"{verdict}\" recorded by chair {chair_user}!")
                    total_verdicts_issued += 1
                else:
                    detail = res.get("detail", "Unknown error")
                    if "Every required faculty and external panel evaluation must be submitted" in detail or "Panel grading must be submitted" in detail:
                        print(f"    [VERDICT PENDING] {t_name} (Schedule #{sched_id}): Awaiting remaining panelist evaluations.")
                        total_verdicts_pending += 1
                    else:
                        print(f"    [VERDICT SKIP] {t_name} (Schedule #{sched_id}): {detail}")
                        total_failed += 1
                    if res.get('code') in (401, 429):
                        abort_batch = True
                        break
                time.sleep(args.delay)

    print("\n" + "=" * 70)
    print("  Panelist Evaluation Summary")
    print("=" * 70)
    print(f"  Evaluations {'Planned' if args.dry_run else 'Created'} : {total_submitted}")
    print(f"  Already Graded      : {total_skipped}")
    print(f"  Unavailable         : {total_unavailable}")
    print(f"  Failed              : {total_failed}")
    if not args.no_verdict and capstone_schedules:
        print(f"  Verdicts {'Planned' if args.dry_run else 'Recorded'}   : {total_verdicts_issued}")
        print(f"  Verdicts Existing   : {total_verdicts_skipped}")
        print(f"  Verdicts Pending    : {total_verdicts_pending}")
    print("=" * 70)
    if total_failed:
        if abort_batch:
            print('[STOPPED] Authentication/rate-limit failure; remaining submissions and verdicts were not attempted.')
        return 1
    if total_unavailable or total_verdicts_pending:
        print("[PENDING] Some assignments need attention; see the reasons above.")
        return 2
    if total_submitted > 0 or total_verdicts_issued > 0:
        print("[OK] Preview completed; no grades or verdicts were saved." if args.dry_run
              else "[OK] Panelist automation completed! Refresh your browser to verify.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(run())
    except (ValueError, common.UploadError, requests.RequestException) as exc:
        print(f"[FAIL] {exc}")
        sys.exit(1)
