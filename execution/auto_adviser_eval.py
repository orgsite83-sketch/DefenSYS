"""
Automate Adviser Grading over HTTP REST API.

Simulates faculty advisers submitting evaluations for their advised capstone teams via the
actual DefenSYS backend API endpoints:
  - Fetches advised teams: GET /api/grading/grades/adviser-grades/
  - Generates random criteria scores (default: 7 to 9 out of 10)
  - Submits evaluations: POST /api/grading/grades/adviser-grades/<grade_id>/submit/

Usage Examples:
  # 1. Run for all advised teams across all advisers:
  python execution/auto_adviser_eval.py --all-advisers --min-score 7 --max-score 9

  # 2. Dry-run first to preview evaluations without saving:
  python execution/auto_adviser_eval.py --all-advisers --dry-run

  # 3. Target a specific team by Team ID:
  python execution/auto_adviser_eval.py --team-id 3 --min-score 7 --max-score 9

  # 4. Target specific adviser usernames:
  python execution/auto_adviser_eval.py --advisers 206 208 --min-score 7 --max-score 9
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
        description="Automate adviser evaluations across advised capstone teams using random scores."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="Base URL of DefenSYS backend (default: http://127.0.0.1:8000)",
    )
    parser.add_argument(
        "--all-advisers",
        action="store_true",
        help="Automatically evaluate advised teams for all faculty advisers",
    )
    parser.add_argument(
        "--advisers",
        nargs="+",
        help="Specific adviser usernames to run (e.g. --advisers 206 208)",
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


def fetch_adviser_users(specific_usernames: Optional[List[str]] = None, team_id: Optional[int] = None) -> List[str]:
    init_django()
    from django.contrib.auth import get_user_model  # type: ignore
    from student_teams.models import StudentTeam  # type: ignore

    User = get_user_model()

    if specific_usernames:
        return [
            u.username
            for u in User.objects.filter(role__in=["faculty", "admin"], username__in=specific_usernames).order_by("username")
        ]

    qs = StudentTeam.objects.filter(adviser__isnull=False)
    if team_id:
        qs = qs.filter(pk=team_id)

    adviser_ids = qs.values_list("adviser__username", flat=True).distinct()
    return sorted(list(set(a for a in adviser_ids if a)))


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

    specific_advisers = None
    if args.advisers:
        specific_advisers = []
        for a in args.advisers:
            specific_advisers.extend([u.strip() for u in a.split(",") if u.strip()])

    if not args.all_advisers and not specific_advisers and not args.team_id:
        print("[!] Error: Specify --all-advisers, --advisers <id...>, or --team-id <id>.")
        sys.exit(1)

    print("[*] Discovering faculty advisers...")
    adviser_usernames = fetch_adviser_users(specific_advisers, args.team_id)

    if not adviser_usernames:
        print("[!] No faculty adviser records found.")
        sys.exit(1)

    min_s = int(round(args.min_score))
    max_s = int(round(args.max_score))

    print("=" * 70)
    print("  DefenSYS Adviser Evaluation Automation")
    print("=" * 70)
    print(f"  Target Server   : {args.base_url}")
    print(f"  Total Advisers  : {len(adviser_usernames)}")
    print(f"  Score Range     : {min_s} to {max_s} per criterion")
    print(f"  Mode            : {'DRY RUN (No changes saved)' if args.dry_run else 'LIVE SUBMISSION'}")
    print("=" * 70)

    total_submitted = 0
    total_skipped = 0

    for idx, username in enumerate(adviser_usernames, 1):
        token = get_jwt_token_for_user(username)
        if not token:
            continue

        session = requests.Session()
        session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

        url = f"{args.base_url.rstrip('/')}/api/grading/grades/adviser-grades/"
        try:
            resp = session.get(url, timeout=10)
            if resp.status_code != 200:
                print(f"  [✗] Failed to fetch advised teams for adviser {username} (HTTP {resp.status_code})")
                continue
            data = resp.json()
        except Exception as e:
            print(f"  [✗] Error connecting to API: {e}")
            continue

        results = data.get("grades") or data.get("results") or []
        if args.team_id:
            results = [r for r in results if r.get("team_id") == args.team_id or r.get("team") == str(args.team_id)]

        print(f"\n[{idx}/{len(adviser_usernames)}] Adviser: {username} (Advised Teams: {len(results)})")

        for grade_row in results:
            grade_id = grade_row.get("id")
            team_name = grade_row.get("team_name") or grade_row.get("team") or f"Grade #{grade_id}"
            adviser_score = grade_row.get("adviser_score")

            if adviser_score is not None:
                print(f"  [-] {team_name} already graded ({float(adviser_score):.2f}%). Skipping.")
                total_skipped += 1
                continue

            rubric_id = grade_row.get("assigned_adviser_rubric_id")
            rubric_name = grade_row.get("assigned_adviser_rubric_name") or "Adviser Rubric"
            target_type = grade_row.get("assigned_adviser_rubric_target_type") or "team"
            criteria = grade_row.get("assigned_adviser_criteria") or []
            members = grade_row.get("members") or []

            if not criteria or not rubric_id:
                print(f"  [!] No adviser rubric assigned for {team_name}. Skipping.")
                continue

            def generate_scores(criterion_list):
                scores = []
                for i, c in enumerate(criterion_list):
                    c_name = c["name"]
                    c_max = float(c.get("max_score", 10.0))
                    if c_max >= max_s:
                        s = random.randint(min_s, max_s)
                    else:
                        ratio = random.uniform(min_s / 10.0, max_s / 10.0)
                        s = max(1, min(int(round(c_max * ratio)), int(c_max)))
                    scores.append({
                        "criterion_name": c_name,
                        "score": float(s),
                        "max_score": float(c_max),
                        "display_order": i,
                    })
                return scores

            payload = {
                "rubric_id": rubric_id,
                "team_criteria_scores": [],
                "student_submissions": [],
            }

            if target_type == "team":
                payload["team_criteria_scores"] = generate_scores(criteria)
            elif target_type == "individual":
                for m in members:
                    s_id = m.get("student_id") or m.get("id")
                    payload["student_submissions"].append({
                        "student_id": s_id,
                        "criteria_scores": generate_scores(criteria),
                    })
            else:  # 'both'
                team_criteria = [c for c in criteria if c.get("target_type") == "team"]
                ind_criteria = [c for c in criteria if c.get("target_type") == "individual"]
                if team_criteria:
                    payload["team_criteria_scores"] = generate_scores(team_criteria)
                for m in members:
                    s_id = m.get("student_id") or m.get("id")
                    if ind_criteria:
                        payload["student_submissions"].append({
                            "student_id": s_id,
                            "criteria_scores": generate_scores(ind_criteria),
                        })

            if args.dry_run:
                print(f"    [DRY-RUN] Would submit adviser grade for {team_name} using rubric '{rubric_name}' ({target_type})")
                total_submitted += 1
            else:
                submit_url = f"{args.base_url.rstrip('/')}/api/grading/grades/adviser-grades/{grade_id}/submit/"
                try:
                    s_resp = session.post(submit_url, json=payload, timeout=10)
                    if s_resp.status_code in (200, 201):
                        res_data = s_resp.json()
                        new_score = res_data.get("adviser_score")
                        score_str = f"Score: {float(new_score):.2f}%" if new_score is not None else "Saved"
                        print(f"    [OK] {team_name}: Submitted successfully! ({score_str})")
                        total_submitted += 1
                    else:
                        print(f"    [FAIL] Failed to submit for {team_name} (HTTP {s_resp.status_code}): {s_resp.text}")
                except Exception as e:
                    print(f"    [FAIL] Network error submitting for {team_name}: {e}")

            time.sleep(args.delay)

    print("\n" + "=" * 70)
    print("  Adviser Evaluation Summary")
    print("=" * 70)
    print(f"  Evaluations Created : {total_submitted}")
    print(f"  Already Graded      : {total_skipped}")
    print("=" * 70)
    if total_submitted > 0:
        print("[OK] Adviser evaluations submitted! Refresh your browser to verify.")


if __name__ == "__main__":
    run()
