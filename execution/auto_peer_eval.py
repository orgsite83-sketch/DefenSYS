"""
Automate Student Peer Evaluations over HTTP REST API.

Simulates students submitting peer evaluations for their teammates via the actual
DefenSYS backend API endpoints:
  - Fetches dashboard: GET /api/dashboards/student/
  - Generates random criteria scores (default: 6 to 9 out of 10)
  - Submits evaluations: POST /api/grading/grades/peer-evaluations/

Usage Examples:
  # 1. Evaluate all 64 students in the database with scores between 6 and 9:
  python execution/auto_peer_eval.py --all-students --min-score 6 --max-score 9

  # 2. Dry-run first to preview the evaluations without saving:
  python execution/auto_peer_eval.py --all-students --min-score 6 --max-score 9 --dry-run

  # 3. Target a single team by Team ID:
  python execution/auto_peer_eval.py --team-id 1 --min-score 6 --max-score 9

  # 4. Target specific student usernames:
  python execution/auto_peer_eval.py --students 4001 4002 4003 4004 --min-score 6 --max-score 9

  # 5. Connect to a custom server IP/port (e.g., LAN):
  python execution/auto_peer_eval.py --base-url http://192.168.1.3:8000 --all-students
"""

import argparse
import os
import random
import sys
import time
from typing import Dict, List, Optional, Tuple
import requests

# Ensure backend directory is in sys.path for Django model access
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BACKEND_PATH = os.path.join(REPO_ROOT, "backend")
if BACKEND_PATH not in sys.path:
    sys.path.insert(0, BACKEND_PATH)


def init_django():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "defensys_backend.settings")
    import django
    django.setup()


def parse_args():
    parser = argparse.ArgumentParser(
        description="Automate peer evaluations across student teams using random scores."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="Base URL of DefenSYS backend (default: http://127.0.0.1:8000)",
    )
    parser.add_argument(
        "--all-students",
        action="store_true",
        help="Automatically evaluate all active student accounts in the database (e.g. all 64 students)",
    )
    parser.add_argument(
        "--students",
        nargs="+",
        help="Specific student usernames to run (e.g. --students 4001 4002 4003)",
    )
    parser.add_argument(
        "--team-id",
        type=int,
        help="Filter to students belonging to a specific Team ID",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=6.0,
        help="Minimum criterion score (default: 6.0)",
    )
    parser.add_argument(
        "--max-score",
        type=float,
        default=9.0,
        help="Maximum criterion score (default: 9.0)",
    )
    parser.add_argument(
        "--stage",
        help="Optional stage label override (e.g. 'Concept Proposal'). Defaults to current active stage.",
    )
    parser.add_argument(
        "--http-login",
        action="store_true",
        help="Use HTTP POST /api/login/ instead of direct JWT token generation (note: subject to 30/min rate throttle)",
    )
    parser.add_argument(
        "--password",
        help="Student password for HTTP login (defaults to each student's username if not specified)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Limit the number of student accounts to process (e.g. --limit 5)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be evaluated without submitting to the API",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.05,
        help="Delay in seconds between requests (default: 0.05s)",
    )
    return parser.parse_args()


def fetch_student_records(team_id: Optional[int] = None, specific_usernames: Optional[List[str]] = None) -> List[Tuple[str, str]]:
    """
    Returns a list of (username, password) tuples from Django database (read-only).
    Student passwords default to their username in DefenSYS.
    """
    init_django()
    from django.contrib.auth import get_user_model
    from student_teams.models import TeamMembership

    User = get_user_model()

    if specific_usernames:
        users = User.objects.filter(role="student", username__in=specific_usernames).order_by("username")
    elif team_id:
        memberships = TeamMembership.objects.filter(team_id=team_id).select_related("student")
        users = [m.student for m in memberships if m.student]
    else:
        # All active students
        users = User.objects.filter(role="student", is_active=True).order_by("username")

    records = []
    for u in users:
        # Default password is the username (student ID number)
        records.append((u.username, u.username))

    return records


def get_jwt_token_for_user(username: str) -> Optional[str]:
    """Generates a valid signed JWT access token directly using Django SimpleJWT."""
    init_django()
    from django.contrib.auth import get_user_model
    from authentication_access_control.tokens import DefensysRefreshToken

    User = get_user_model()
    try:
        user = User.objects.get(username=username)
        refresh = DefensysRefreshToken.for_user(user)
        return str(refresh.access_token)
    except Exception as e:
        print(f"  [✗] Failed to generate token for {username}: {e}")
        return None


class StudentClient:
    def __init__(self, base_url: str, username: str, password: Optional[str] = None):
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.password = password or username
        self.session = requests.Session()
        self.access_token: Optional[str] = None

    def authenticate(self, use_http_login: bool = False) -> bool:
        if not use_http_login:
            # Fast, direct JWT token generation (no rate limiting!)
            self.access_token = get_jwt_token_for_user(self.username)
            if self.access_token:
                self.session.headers.update({
                    "Authorization": f"Bearer {self.access_token}",
                    "Content-Type": "application/json",
                })
                return True
            return False

        # Fallback to HTTP POST /api/login/
        url = f"{self.base_url}/api/login/"
        payload = {"username": self.username, "password": self.password}
        try:
            resp = self.session.post(url, json=payload, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                self.access_token = data.get("access")
                self.session.headers.update({
                    "Authorization": f"Bearer {self.access_token}",
                    "Content-Type": "application/json",
                })
                return True
            elif resp.status_code == 429:
                print(f"  [!] HTTP 429 Rate Throttled on login for '{self.username}'. Sleeping 5s...")
                time.sleep(5)
                return self.authenticate(use_http_login=True)
            else:
                print(f"  [✗] Login failed for '{self.username}' (HTTP {resp.status_code}): {resp.text}")
                return False
        except Exception as e:
            print(f"  [✗] Network error logging in as '{self.username}': {e}")
            return False

    def get_dashboard(self) -> Optional[Dict]:
        url = f"{self.base_url}/api/dashboards/student/"
        try:
            resp = self.session.get(url, timeout=10)
            if resp.status_code == 200:
                return resp.json()
            else:
                print(f"  [✗] Failed to fetch dashboard (HTTP {resp.status_code}): {resp.text}")
                return None
        except Exception as e:
            print(f"  [✗] Network error fetching dashboard: {e}")
            return None

    def submit_evaluation(self, payload: Dict, dry_run: bool = False) -> bool:
        if dry_run:
            return True

        url = f"{self.base_url}/api/grading/grades/peer-evaluations/"
        try:
            resp = self.session.post(url, json=payload, timeout=10)
            if resp.status_code == 200:
                return True
            else:
                print(f"  [✗] Failed to submit evaluation (HTTP {resp.status_code}): {resp.text}")
                return False
        except Exception as e:
            print(f"  [✗] Network error submitting evaluation: {e}")
            return False


def run():
    args = parse_args()

    # Determine student list
    specific_users = None
    if args.students:
        specific_users = []
        for s in args.students:
            specific_users.extend([u.strip() for u in s.split(",") if u.strip()])

    if not args.all_students and not specific_users and not args.team_id:
        print("[!] Error: Specify --all-students, --students <id...>, or --team-id <id>.")
        sys.exit(1)

    print(f"[*] Discovering student accounts...")
    student_records = fetch_student_records(team_id=args.team_id, specific_usernames=specific_users)

    if not student_records:
        print("[!] No student records found matching the criteria.")
        sys.exit(1)

    if args.limit and args.limit > 0:
        student_records = student_records[:args.limit]

    min_s = int(round(args.min_score))
    max_s = int(round(args.max_score))

    print("=" * 70)
    print("  DefenSYS Peer Evaluation Automation")
    print("=" * 70)
    print(f"  Target Server   : {args.base_url}")
    print(f"  Total Students  : {len(student_records)}")
    print(f"  Score Range     : {min_s} to {max_s} per criterion")
    print(f"  Auth Method     : {'HTTP POST /api/login/' if args.http_login else 'Direct JWT (Fast/No-Throttle)'}")
    print(f"  Mode            : {'DRY RUN (No changes saved)' if args.dry_run else 'LIVE SUBMISSION'}")
    print("=" * 70)

    total_evals_submitted = 0
    total_evals_skipped = 0
    students_processed = 0

    for idx, (username, default_pwd) in enumerate(student_records, 1):
        pwd = args.password or default_pwd
        client = StudentClient(args.base_url, username, pwd)

        if not client.authenticate(use_http_login=args.http_login):
            continue

        dashboard = client.get_dashboard()
        if not dashboard:
            continue

        current_student = dashboard.get("student") or {}
        current_id = current_student.get("id")
        student_name = f"{current_student.get('first_name', '')} {current_student.get('last_name', '')}".strip() or username

        team = dashboard.get("team") or {}
        team_id = team.get("id")
        team_name = team.get("name", "Unknown Team")
        members = team.get("members", [])

        if not team_id or not members:
            # Student not assigned to a team
            continue

        stage = args.stage or dashboard.get("current_stage") or "Concept Proposal"
        peer_criteria = dashboard.get("peerCriteria") or []

        if not peer_criteria:
            # Stage has no peer criteria / peer eval not open
            continue

        # Check existing submissions for this student
        already_submitted = {
            s.get("evaluateeId")
            for s in dashboard.get("myPeerSubmissions", [])
            if s.get("evaluateeId") is not None
        }

        # Filter teammates needing evaluation (exclude self and already submitted)
        teammates_to_rate = [
            m for m in members
            if m.get("id") != current_id and m.get("id") not in already_submitted
        ]

        if not teammates_to_rate:
            total_evals_skipped += (len(members) - 1)
            continue

        students_processed += 1
        print(f"\n[{idx}/{len(student_records)}] Student {username} ({student_name}) — Team: {team_name} [{stage}]")

        for teammate in teammates_to_rate:
            teammate_id = teammate.get("id")
            teammate_name = teammate.get("name") or f"Teammate {teammate_id}"

            # Generate random score between min_score and max_score
            breakdown = []
            for criterion in peer_criteria:
                crit_name = criterion.get("name", "Criterion")
                crit_max = float(criterion.get("maxScore", 10.0))

                # If criterion max is 10, pick directly between min_s and max_s (e.g. 6 to 9)
                if crit_max >= max_s:
                    score = random.randint(min_s, max_s)
                else:
                    # Scale down proportionally if rubric max is e.g. 5
                    ratio = random.uniform(min_s / 10.0, max_s / 10.0)
                    score = max(1, min(int(round(crit_max * ratio)), int(crit_max)))

                breakdown.append({
                    "criteriaName": crit_name,
                    "score": float(score),
                    "max": float(crit_max),
                })

            total_score = sum(b["score"] for b in breakdown)
            max_score = sum(b["max"] for b in breakdown)

            payload = {
                "teamId": int(team_id),
                "evaluateeId": int(teammate_id),
                "stage": stage,
                "breakdown": breakdown,
                "total": total_score,
                "max": max_score,
            }

            scores_desc = ", ".join(f"{b['criteriaName']}: {int(b['score'])}/{int(b['max'])}" for b in breakdown)

            success = client.submit_evaluation(payload, dry_run=args.dry_run)
            if success:
                total_evals_submitted += 1
                prefix = "[DRY-RUN]" if args.dry_run else "✓"
                print(f"    {prefix} Rated {teammate_name}: {total_score:.0f}/{max_score:.0f} [{scores_desc}]")
            else:
                print(f"    ✗ Failed to rate {teammate_name}")

            time.sleep(args.delay)

    print("\n" + "=" * 70)
    print("  Execution Summary")
    print("=" * 70)
    print(f"  Students Evaluated  : {students_processed}")
    print(f"  Evaluations Created : {total_evals_submitted}")
    print(f"  Already Completed   : {total_evals_skipped}")
    print("=" * 70)

    if args.dry_run:
        print("[!] Dry-run complete. Run without --dry-run to apply to the database.")
    elif total_evals_submitted > 0:
        print("[✓] All peer evaluations successfully submitted!")
        print("    Refresh your browser (F5) to see the completed progress and locked cards.")


if __name__ == "__main__":
    run()
