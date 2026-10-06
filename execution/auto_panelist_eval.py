"""
Automate Panelist Grading over HTTP REST API.

Simulates faculty panelists submitting evaluations for defense schedules via the actual
DefenSYS backend API endpoints:
  - Fetches assignments: GET /api/defense/schedules/panelist-assignments/
  - Generates random criteria scores (default: 6 to 9 out of 10)
  - Submits evaluations: POST /api/defense/schedules/submit-grades/

Usage Examples:
  # 1. Run for all assigned panelists:
  python execution/auto_panelist_eval.py --all-panelists --min-score 7 --max-score 9

  # 2. Dry-run first to preview evaluations without saving:
  python execution/auto_panelist_eval.py --all-panelists --dry-run

  # 3. Target a specific team by Team ID:
  python execution/auto_panelist_eval.py --team-id 3 --min-score 7 --max-score 9

  # 4. Target specific panelist usernames:
  python execution/auto_panelist_eval.py --panelists 208 215 --min-score 7 --max-score 9
"""

import argparse
import os
import random
import sys
import time
from typing import Dict, List, Optional
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


def parse_args():
    parser = argparse.ArgumentParser(
        description="Automate defense schedule panel evaluations across teams using random scores."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="Base URL of DefenSYS backend (default: http://127.0.0.1:8000)",
    )
    parser.add_argument(
        "--all-panelists",
        action="store_true",
        help="Automatically evaluate all assigned defense panelists in the active semester",
    )
    parser.add_argument(
        "--panelists",
        nargs="+",
        help="Specific panelist usernames to run (e.g. --panelists 208 215)",
    )
    parser.add_argument(
        "--team-id",
        type=int,
        help="Filter evaluations to a specific Team ID",
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
    return parser.parse_args()


def fetch_panelist_users(specific_usernames: Optional[List[str]] = None, team_id: Optional[int] = None) -> List[str]:
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    from defense.scheduler.models import DefenseSchedule, SchedulePanelist  # type: ignore

    User = get_user_model()

    if specific_usernames:
        return [
            u.username
            for u in User.objects.filter(role__in=["faculty", "admin"], username__in=specific_usernames).order_by("username")
        ]

    qs = SchedulePanelist.objects.select_related("panelist", "schedule")
    if team_id:
        qs = qs.filter(schedule__team_id=team_id)

    panelist_ids = qs.values_list("panelist__username", flat=True).distinct()
    return sorted(list(set(p for p in panelist_ids if p)))


def get_jwt_token_for_user(username: str) -> Optional[str]:
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    from authentication_access_control.tokens import DefensysRefreshToken  # type: ignore

    User = get_user_model()
    try:
        user = User.objects.get(username=username)
        refresh = DefensysRefreshToken.for_user(user)
        return str(refresh.access_token)
    except Exception as e:
        print(f"  [FAIL] Failed to generate token for {username}: {e}")
        return None


def run():
    args = parse_args()

    specific_panelists = None
    if args.panelists:
        specific_panelists = []
        for p in args.panelists:
            specific_panelists.extend([u.strip() for u in p.split(",") if u.strip()])

    if not args.all_panelists and not specific_panelists and not args.team_id:
        print("[!] Error: Specify --all-panelists, --panelists <id...>, or --team-id <id>.")
        sys.exit(1)

    print("[*] Discovering assigned defense panelists...")
    panelist_usernames = fetch_panelist_users(specific_panelists, args.team_id)

    if not panelist_usernames:
        print("[!] No assigned panelist records found.")
        sys.exit(1)

    min_s = int(round(args.min_score))
    max_s = int(round(args.max_score))

    print("=" * 70)
    print("  DefenSYS Panelist Evaluation Automation")
    print("=" * 70)
    print(f"  Target Server   : {args.base_url}")
    print(f"  Total Panelists : {len(panelist_usernames)}")
    print(f"  Score Range     : {min_s} to {max_s} per criterion")
    print(f"  Mode            : {'DRY RUN (No changes saved)' if args.dry_run else 'LIVE SUBMISSION'}")
    print("=" * 70)

    total_submitted = 0
    total_skipped = 0

    remarks_pool = [
        "Well-structured presentation and sound methodology.",
        "Demonstrated strong technical understanding and clear scope.",
        "Solid prototype progress. Feasibility and problem alignment are clear.",
        "Good defense performance. Recommendations noted for next phase.",
    ]

    for idx, username in enumerate(panelist_usernames, 1):
        token = get_jwt_token_for_user(username)
        if not token:
            continue

        session = requests.Session()
        session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

        url = f"{args.base_url.rstrip('/')}/api/defense/schedules/panelist-assignments/"
        try:
            resp = session.get(url, timeout=10)
            if resp.status_code != 200:
                print(f"  [✗] Failed to fetch assignments for panelist {username} (HTTP {resp.status_code})")
                continue
            data = resp.json()
        except Exception as e:
            print(f"  [✗] Error connecting to API: {e}")
            continue

        teams = data.get("teams", [])
        if args.team_id:
            teams = [t for t in teams if t.get("team_id") == args.team_id]

        print(f"\n[{idx}/{len(panelist_usernames)}] Panelist: {username} (Assigned Teams: {len(teams)})")

        for team_payload in teams:
            team_name = team_payload.get("name") or team_payload.get("team_name") or f"Team {team_payload.get('id')}"
            schedule_id = team_payload.get("schedule_id")
            team_id = team_payload.get("id") or team_payload.get("team_id")
            is_posted = team_payload.get("is_posted", False)

            if is_posted:
                print(f"  [-] {team_name} (Schedule #{schedule_id}) already graded. Skipping.")
                total_skipped += 1
                continue

            panel_rubric = team_payload.get("panel_rubric") or {}
            criteria = panel_rubric.get("criteria", [])
            target_type = panel_rubric.get("target_type", "team")
            members = team_payload.get("members", [])
            eval_context = team_payload.get("evaluation_context")

            if not criteria:
                print(f"  [!] No rubric criteria configured for {team_name}. Skipping.")
                continue

            def generate_scores(criterion_list):
                scores = []
                for c in criterion_list:
                    c_id = c["id"]
                    c_max = float(c.get("max_score", 10.0))
                    if c_max >= max_s:
                        s = random.randint(min_s, max_s)
                    else:
                        ratio = random.uniform(min_s / 10.0, max_s / 10.0)
                        s = max(1, min(int(round(c_max * ratio)), int(c_max)))
                    scores.append({"criterion_id": c_id, "score": float(s)})
                return scores

            submissions = []
            remarks = random.choice(remarks_pool)

            if target_type == "team":
                submissions.append({
                    "student_id": None,
                    "criteria_scores": generate_scores(criteria),
                    "remarks": remarks,
                })
            elif target_type == "individual":
                for m in members:
                    submissions.append({
                        "student_id": m["id"],
                        "criteria_scores": generate_scores(criteria),
                        "remarks": f"{remarks} ({m.get('name')})",
                    })
            else:  # 'both'
                team_criteria = [c for c in criteria if c.get("target_type") == "team"]
                ind_criteria = [c for c in criteria if c.get("target_type") == "individual"]
                if team_criteria:
                    submissions.append({
                        "student_id": None,
                        "criteria_scores": generate_scores(team_criteria),
                        "remarks": remarks,
                    })
                for m in members:
                    if ind_criteria:
                        submissions.append({
                            "student_id": m["id"],
                            "criteria_scores": generate_scores(ind_criteria),
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
            else:
                submit_url = f"{args.base_url.rstrip('/')}/api/defense/schedules/submit-grades/"
                try:
                    s_resp = session.post(submit_url, json=payload, timeout=10)
                    if s_resp.status_code in (200, 201):
                        res_data = s_resp.json()
                        p_score = res_data.get("panel_score")
                        score_str = f"Score: {p_score:.2f}%" if p_score is not None else "Saved"
                        print(f"    [OK] {team_name}: Submitted successfully! ({score_str})")
                        total_submitted += 1
                    else:
                        print(f"    [FAIL] Failed to submit for {team_name} (HTTP {s_resp.status_code}): {s_resp.text}")
                except Exception as e:
                    print(f"    [FAIL] Network error submitting for {team_name}: {e}")

            time.sleep(args.delay)

    print("\n" + "=" * 70)
    print("  Panelist Evaluation Summary")
    print("=" * 70)
    print(f"  Evaluations Created : {total_submitted}")
    print(f"  Already Graded      : {total_skipped}")
    print("=" * 70)
    if total_submitted > 0:
        print("[OK] Panelist evaluations submitted! Refresh your browser to verify.")


if __name__ == "__main__":
    run()
