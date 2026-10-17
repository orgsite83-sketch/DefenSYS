"""
Automate Panelist Grading and Defense Verdicts over HTTP REST API.

Simulates faculty and assigned external panelists submitting evaluations via the actual
DefenSYS backend API endpoints:
  - Fetches assignments: GET /api/defense/schedules/panelist-assignments/
  - Generates criteria scores (default: 7 to 9 out of 10)
  - Submits evaluations: POST /api/defense/schedules/submit-grades/
  - External invitations use guest-assignments/ and guest-submit-grades/ with guest JWTs
  - Issues official Capstone defense verdict (chair/admin): PATCH /api/defense/schedules/<schedule_id>/verdict/
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

  # 5. Only evaluate PIT events (scores only, no verdicts):
  python execution/auto_panelist_eval.py --all-panelists --scope pit

  # 6. Specify Capstone verdict outcome (default: approved):
  python execution/auto_panelist_eval.py --all-panelists --scope capstone --verdict approved_with_revisions

  # 7. Issue verdicts only for Capstone defenses whose panel scores are already posted:
  python execution/auto_panelist_eval.py --all-panelists --verdict-only

  # 8. Fill only missing external evaluations for one PIT event:
  python execution/auto_panelist_eval.py --external-only --scope pit --stage "PIT System Prototype Showcase" --dry-run

Exit codes: 0 = completed, 1 = failed request/configuration, 2 = unavailable evaluations or pending verdicts.
Dry runs use GET requests only and do not create refresh-token records.
"""

import argparse
from datetime import date, timedelta
import math
import os
import random
import sys
import time
from typing import Any, Dict, List, Optional
import requests

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


DEFAULT_VERDICT_REMARKS = {
    "approved": "Approved by panel deliberation. Proceed to final manuscript submission.",
    "approved_with_revisions": "Approved with revisions. Comply with all panel recommendations by deadline.",
    "for_redefense": "For re-defense. Re-defense required following revision of methodology and prototypes.",
    "failed": "Failed to meet minimum defense requirements.",
    "project_rejected": "Project concept and implementation rejected.",
}


def parse_args():
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
        default="approved",
        choices=["approved", "approved_with_revisions", "for_redefense", "failed", "project_rejected"],
        help="Verdict to issue for completed Capstone defenses (default: approved)",
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
    args = parser.parse_args()
    if not (math.isfinite(args.min_score) and math.isfinite(args.max_score)
            and 0 <= args.min_score <= args.max_score <= 10):
        parser.error("Scores must satisfy 0 <= --min-score <= --max-score <= 10 (scaled to each criterion maximum).")
    if not math.isfinite(args.delay) or args.delay < 0:
        parser.error("--delay must be a non-negative finite number.")
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


def fetch_target_schedule_ids(team_id=None, stage=None, session_id=None, semester_id=None, scope=None):
    """One authoritative allowlist for discovery and every API assignment response."""
    init_django()
    from django.db.models import Q
    from defense.scheduler.models import DefenseSchedule
    from academic_period_management.services import active_semester

    qs = DefenseSchedule.objects.filter(status=DefenseSchedule.STATUS_SCHEDULED)
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
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    from defense.scheduler.models import SchedulePanelist  # type: ignore

    User = get_user_model()

    if schedule_ids is None:
        schedule_ids = fetch_target_schedule_ids(team_id, stage, session_id, semester_id, scope)
    users = User.objects.filter(is_active=True, role__in=['faculty', 'admin'],
        pk__in=SchedulePanelist.objects.filter(schedule_id__in=schedule_ids).values('panelist_id'))
    if specific_usernames:
        users = users.filter(username__in=specific_usernames)
    return list(users.order_by('username').values_list('username', flat=True))


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
    return [{'criterion_id': c['id'],
             'score': round(min(float(c.get('max_score', 10)),
                                random.uniform(minimum, maximum) / 10 * float(c.get('max_score', 10))), 2)}
            for c in criteria]


def get_jwt_token_for_user(username: str) -> Optional[str]:
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    from rest_framework_simplejwt.tokens import AccessToken  # type: ignore

    User = get_user_model()
    try:
        user = User.objects.get(username=username, is_active=True)
        # A short-lived access token does not insert an OutstandingToken row in dry runs.
        return str(AccessToken.for_user(user))
    except Exception as e:
        print(f"  [FAIL] Failed to generate token for {username}: {e}")
        return None


def get_schedule_chair_username(schedule_id: int) -> Optional[str]:
    init_django()
    from defense.scheduler.models import SchedulePanelist  # type: ignore
    chair_sp = (
        SchedulePanelist.objects.filter(schedule_id=schedule_id, is_chair=True, panelist__is_active=True)
        .select_related("panelist")
        .first()
    )
    if chair_sp and chair_sp.panelist:
        return chair_sp.panelist.username
    return None


def get_admin_username() -> Optional[str]:
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    User = get_user_model()
    admin = User.objects.filter(role="admin", is_active=True).order_by("id").first()
    if not admin:
        admin = User.objects.filter(is_superuser=True, is_active=True).order_by("id").first()
    return admin.username if admin else None


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
        return {"status": "error", "detail": "No authorized panel chair or administrator available."}

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
            revision_deadline = (date.today() + timedelta(days=14)).isoformat()
        payload["revision_deadline"] = revision_deadline

    url = f"{base_url.rstrip('/')}/api/defense/schedules/{schedule_id}/verdict/"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    try:
        resp = requests.patch(url, json=payload, headers=headers, timeout=10)
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


def run():
    args = parse_args()

    specific_panelists = None
    if args.panelists:
        specific_panelists = []
        for p in args.panelists:
            specific_panelists.extend([u.strip() for u in p.split(",") if u.strip()])

    if not args.all_panelists and not specific_panelists and not args.team_id and not args.session_id and not args.external_only:
        print("[!] Error: Specify --all-panelists, --external-only, --panelists <username...>, --team-id <id>, or --session-id <uuid>.")
        sys.exit(1)

    print("[*] Discovering assigned defense panelists...")
    schedule_ids = fetch_target_schedule_ids(args.team_id, args.stage, args.session_id, args.semester_id, args.scope)
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
        print("[!] No matching assigned panelist records found.")
        sys.exit(1)

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
    if args.stage:
        print(f"  Stage Filter    : {args.stage}")
    if args.session_id:
        print(f"  Session UUID    : {args.session_id}")
    if args.semester_id:
        print(f"  Semester ID     : {args.semester_id}")
    if not args.no_verdict:
        print(f"  Capstone Verdict: {args.verdict.upper()} (chair/admin submission)")
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

    remarks_pool = [
        "Well-structured presentation and sound methodology.",
        "Demonstrated strong technical understanding and clear scope.",
        "Solid prototype progress. Feasibility and problem alignment are clear.",
        "Good defense performance. Recommendations noted for next phase.",
    ]

    for idx, actor in enumerate(actors, 1):
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
            resp = session.get(url, timeout=10)
            if resp.status_code != 200:
                print(f"  [✗] Failed to fetch assignments for panelist {username} (HTTP {resp.status_code})")
                total_failed += 1
                session.close()
                continue
            data = resp.json()
        except Exception as e:
            print(f"  [✗] Error connecting to API: {e}")
            total_failed += 1
            session.close()
            continue

        teams = data.get("teams", [])

        # Filter teams locally
        filtered_teams = []
        for t in teams:
            if t.get('schedule_id') not in allowed_schedules:
                continue
            t_team_id = t.get("id") or t.get("team_id")
            t_scope = t.get("scope") or ("capstone" if t.get("is_capstone") else "pit")
            t_stage = t.get("defense_stage") or ""
            t_sess = t.get("session_id") or ""
            t_sem = t.get("semester_id")

            if args.team_id and t_team_id != args.team_id:
                continue
            if args.stage and str(t_stage).strip().casefold() != args.stage.strip().casefold():
                continue
            if args.session_id and str(t_sess) != str(args.session_id):
                continue
            if args.semester_id and t_sem != args.semester_id:
                continue
            if args.scope and str(t_scope).strip().casefold() != args.scope.strip().casefold():
                continue

            filtered_teams.append(t)

        print(f"\n[{idx}/{len(actors)}] Panelist: {username} (Matching Teams: {len(filtered_teams)})")

        for team_payload in filtered_teams:
            team_name = team_payload.get("name") or team_payload.get("team_name") or f"Team {team_payload.get('id')}"
            schedule_id = team_payload.get("schedule_id")
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
                continue

            # Check backend eligibility to avoid unwanted data or locked evaluation errors
            if team_payload.get("grading_available") is not True:
                reason = team_payload.get("grading_unavailable_reason") or "Grading is currently unavailable for this schedule."
                print(f"  [SKIP] {team_name} (Schedule #{schedule_id}): {reason}")
                total_unavailable += 1
                continue

            panel_rubric = team_payload.get("panel_rubric") or {}
            criteria = panel_rubric.get("criteria", [])
            target_type = panel_rubric.get("target_type", "team")
            members = team_payload.get("members", [])
            eval_context = team_payload.get("evaluation_context")

            if not criteria:
                print(f"  [!] No rubric criteria configured for {team_name}. Skipping.")
                total_unavailable += 1
                continue

            submissions = []
            remarks = random.choice(remarks_pool)

            if target_type == "team":
                submissions.append({
                    "student_id": None,
                    "criteria_scores": generate_scores(criteria, min_s, max_s),
                    "remarks": remarks,
                })
            elif target_type == "individual":
                for m in members:
                    submissions.append({
                        "student_id": m["id"],
                        "criteria_scores": generate_scores(criteria, min_s, max_s),
                        "remarks": f"{remarks} ({m.get('name')})",
                    })
            else:  # 'both'
                team_criteria = [c for c in criteria if c.get("target_type") == "team"]
                ind_criteria = [c for c in criteria if c.get("target_type") == "individual"]
                if team_criteria:
                    submissions.append({
                        "student_id": None,
                        "criteria_scores": generate_scores(team_criteria, min_s, max_s),
                        "remarks": remarks,
                    })
                for m in members:
                    if ind_criteria:
                        submissions.append({
                            "student_id": m["id"],
                            "criteria_scores": generate_scores(ind_criteria, min_s, max_s),
                            "remarks": f"Individual contribution: {m.get('name')}",
                        })

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
                    s_resp = session.post(submit_url, json=payload, timeout=10)
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
                except Exception as e:
                    print(f"    [FAIL] Network error submitting for {team_name}: {e}")
                    total_failed += 1

            time.sleep(args.delay)
        session.close()

    # Phase 2: Capstone Defense Verdict Processing
    if not args.no_verdict and capstone_schedules:
        print("\n" + "=" * 70)
        print("  Phase 2: Capstone Defense Verdict Processing")
        print("=" * 70)

        for sched_id, sched_info in sorted(capstone_schedules.items()):
            t_name = sched_info["team_name"]
            existing_verdict = sched_info.get("verdict")

            if existing_verdict:
                print(f"  [-] {t_name} (Schedule #{sched_id}) already has verdict: \"{existing_verdict}\". Skipping.")
                total_verdicts_skipped += 1
                continue

            chair_user = get_schedule_chair_username(sched_id)
            if not chair_user:
                chair_user = get_admin_username()

            if not chair_user:
                print(f"  [!] {t_name} (Schedule #{sched_id}): No panel chair or admin found to issue verdict.")
                total_failed += 1
                continue

            verdict_remarks = args.verdict_remarks or DEFAULT_VERDICT_REMARKS.get(
                args.verdict, "Evaluated by panel deliberation."
            )

            if args.dry_run:
                print(f"    [DRY-RUN] Would request verdict \"{args.verdict}\" for {t_name} (Schedule #{sched_id}) as {chair_user}, once every required panel evaluation is complete.")
                total_verdicts_issued += 1
            else:
                res = submit_schedule_verdict(
                    base_url=args.base_url,
                    schedule_id=sched_id,
                    verdict=args.verdict,
                    remarks=verdict_remarks,
                    revision_deadline=args.revision_deadline,
                    redefense_verification=args.redefense_verification,
                    actor_username=chair_user,
                    dry_run=args.dry_run,
                )
                if res.get("status") == "ok":
                    print(f"    [VERDICT OK] {t_name} (Schedule #{sched_id}): Defense verdict \"{args.verdict}\" recorded by chair {chair_user}!")
                    total_verdicts_issued += 1
                else:
                    detail = res.get("detail", "Unknown error")
                    if "Every required faculty and external panel evaluation must be submitted" in detail or "Panel grading must be submitted" in detail:
                        print(f"    [VERDICT PENDING] {t_name} (Schedule #{sched_id}): Awaiting remaining panelist evaluations.")
                        total_verdicts_pending += 1
                    else:
                        print(f"    [VERDICT SKIP] {t_name} (Schedule #{sched_id}): {detail}")
                        total_failed += 1
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
    except (ValueError, requests.RequestException) as exc:
        print(f"[FAIL] {exc}")
        sys.exit(1)
