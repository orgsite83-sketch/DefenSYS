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
import math
import os
import random
import sys
import time
from typing import Dict, List, Optional
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
        help="Minimum rating out of 10, scaled to each criterion maximum (default: 7.0)",
    )
    parser.add_argument(
        "--max-score",
        type=float,
        default=9.0,
        help="Maximum rating out of 10, scaled to each criterion maximum (default: 9.0)",
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
    parser.add_argument('--stage', help='Only grade this defense stage.')
    parser.add_argument('--session-id', help='Only grade teams in this scheduled session UUID.')
    parser.add_argument('--semester-id', type=int, help='Only grade teams in this academic term.')
    parser.add_argument('--request-timeout', type=float, default=30,
        help='HTTP request timeout in seconds (default: 30). Writes are never retried automatically.')
    args = parser.parse_args(argv)
    if not (math.isfinite(args.min_score) and math.isfinite(args.max_score)
            and 0 <= args.min_score <= args.max_score <= 10):
        parser.error('Scores must satisfy 0 <= --min-score <= --max-score <= 10 (scaled to each criterion maximum).')
    if not math.isfinite(args.delay) or not 0 <= args.delay <= 60:
        parser.error('--delay must be a finite number between 0 and 60 seconds.')
    if not math.isfinite(args.request_timeout) or not 0 < args.request_timeout <= 300:
        parser.error('--request-timeout must be a finite number greater than 0 and at most 300 seconds.')
    return args


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
    from rest_framework_simplejwt.tokens import AccessToken  # type: ignore

    User = get_user_model()
    try:
        with common.local_read_only():
            user = User.objects.get(username=username, role__in=['faculty', 'admin'], is_active=True)
            return str(AccessToken.for_user(user))
    except Exception as e:
        print(f"  [FAIL] Failed to generate token for {username}: {e}")
        return None


def generate_scores(criteria, minimum, maximum):
    """Send raw scores with rubric identities; the backend applies saved weights."""
    scores = []
    for index, criterion in enumerate(criteria):
        criterion_max = float(criterion.get('max_score', 10))
        if not math.isfinite(criterion_max) or criterion_max <= 0:
            raise ValueError('The assigned adviser rubric contains an invalid criterion maximum.')
        score = min(criterion_max, max(0, round(random.uniform(minimum, maximum) / 10 * criterion_max, 2)))
        row = {'criterion_name': criterion['name'], 'section': criterion.get('section', ''),
               'score': score, 'max_score': criterion_max, 'display_order': index}
        if criterion.get('id') is not None:
            row['criterion_id'] = criterion['id']
        scores.append(row)
    return scores


def build_payload(grade, minimum, maximum):
    rubric_id = grade.get('assigned_adviser_rubric_id')
    criteria = grade.get('assigned_adviser_criteria') or []
    target = grade.get('assigned_adviser_rubric_target_type') or 'team'
    if not rubric_id or not isinstance(criteria, list) or not criteria:
        raise ValueError('No adviser rubric criteria are assigned.')
    if target not in ('team', 'individual', 'both'):
        raise ValueError('The assigned adviser rubric has an unsupported grading target.')
    ids = [criterion['id'] for criterion in criteria if criterion.get('id') is not None]
    if len(ids) != len(set(ids)):
        raise ValueError('The assigned adviser rubric contains duplicate criterion IDs.')
    members = grade.get('members') or []
    member_ids = [member.get('student_id') or member.get('id') for member in members]
    if target != 'team' and (not member_ids or any(value is None for value in member_ids)
                              or len(member_ids) != len(set(member_ids))):
        raise ValueError('A complete, unique team membership is required for individual grading.')
    payload = {'rubric_id': rubric_id, 'team_criteria_scores': [], 'student_submissions': []}
    if target == 'both':
        if any(criterion.get('target_type') not in ('team', 'individual') for criterion in criteria):
            raise ValueError('The assigned mixed rubric contains an unsupported criterion target.')
        shared = [criterion for criterion in criteria if criterion['target_type'] == 'team']
        individual = [criterion for criterion in criteria if criterion['target_type'] == 'individual']
        if not shared or not individual:
            raise ValueError('A mixed adviser rubric requires both team and individual criteria.')
    else:
        shared = criteria if target == 'team' else []
        individual = criteria if target == 'individual' else []
    if shared:
        payload['team_criteria_scores'] = generate_scores(shared, minimum, maximum)
    if individual:
        payload['student_submissions'] = [
            {'student_id': student_id, 'criteria_scores': generate_scores(individual, minimum, maximum)}
            for student_id in member_ids
        ]
    return payload


def run():
    args = parse_args()
    args.base_url = common.server_url(args.base_url)
    request_timeout = getattr(args, 'request_timeout', 30)

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

    min_s = args.min_score
    max_s = args.max_score

    print("=" * 70)
    print("  DefenSYS Adviser Evaluation Automation")
    print("=" * 70)
    print(f"  Target Server   : {args.base_url}")
    print(f"  Total Advisers  : {len(adviser_usernames)}")
    print(f"  Score Range     : {min_s} to {max_s} out of 10 (scaled per criterion)")
    print(f"  Mode            : {'DRY RUN (No changes saved)' if args.dry_run else 'LIVE SUBMISSION'}")
    print("=" * 70)

    total_submitted = 0
    total_skipped = 0
    total_unavailable = 0
    total_failed = 0
    total_accounts_failed = 0
    abort_batch = False

    for idx, username in enumerate(adviser_usernames, 1):
        if abort_batch:
            break
        token = get_jwt_token_for_user(username)
        if not token:
            total_accounts_failed += 1
            continue

        session = requests.Session()
        session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })

        url = f"{args.base_url.rstrip('/')}/api/grading/grades/adviser-grades/"
        try:
            resp = session.get(url, timeout=request_timeout, allow_redirects=False)
            if resp.status_code != 200:
                print(f"  [✗] Failed to fetch advised teams for adviser {username} (HTTP {resp.status_code})")
                total_accounts_failed += 1
                abort_batch = resp.status_code in (401, 429)
                session.close()
                continue
            data = resp.json()
            if not isinstance(data, dict) or not isinstance(data.get('grades', data.get('results')), list):
                raise ValueError('The adviser API returned an invalid grade list.')
        except Exception as e:
            print(f"  [✗] Error connecting to API: {e}")
            total_accounts_failed += 1
            session.close()
            continue

        results = data.get("grades") or data.get("results") or []
        if args.team_id:
            results = [r for r in results if r.get("team_id") == args.team_id or r.get("team") == str(args.team_id)]

        print(f"\n[{idx}/{len(adviser_usernames)}] Adviser: {username} (Advised Teams: {len(results)})")

        for grade_row in results:
            if args.stage and str(grade_row.get('stage_label') or '').strip().casefold() != args.stage.strip().casefold():
                continue
            if args.session_id and str(grade_row.get('session_id') or '') != args.session_id:
                continue
            if args.semester_id and grade_row.get('semester_id') != args.semester_id:
                continue
            grade_id = grade_row.get("id")
            team_name = grade_row.get("team_name") or grade_row.get("team") or f"Grade #{grade_id}"
            adviser_score = grade_row.get("adviser_score")

            if adviser_score is not None:
                print(f"  [-] {team_name} already graded ({float(adviser_score):.2f}%). Skipping.")
                total_skipped += 1
                continue

            if grade_row.get("adviser_grading_available") is not True:
                reason = grade_row.get("adviser_grading_unavailable_reason") or "Adviser grading is not open for this team."
                print(f"  [SKIP] {team_name}: {reason}")
                total_unavailable += 1
                continue

            rubric_name = grade_row.get("assigned_adviser_rubric_name") or "Adviser Rubric"
            target_type = grade_row.get("assigned_adviser_rubric_target_type") or "team"
            try:
                payload = build_payload(grade_row, min_s, max_s)
            except (ValueError, TypeError, KeyError) as error:
                print(f'    [FAIL] {team_name}: {error}')
                total_failed += 1
                continue

            if args.dry_run:
                print(f"    [DRY-RUN] Would submit adviser grade for {team_name} using rubric '{rubric_name}' ({target_type})")
                total_submitted += 1
            else:
                submit_url = f"{args.base_url.rstrip('/')}/api/grading/grades/adviser-grades/{grade_id}/submit/"
                try:
                    s_resp = session.post(submit_url, json=payload, timeout=request_timeout, allow_redirects=False)
                    if s_resp.status_code in (200, 201):
                        res_data = s_resp.json()
                        new_score = (res_data.get('grade') or res_data).get('adviser_score')
                        score_str = f"Score: {float(new_score):.2f}%" if new_score is not None else "Saved"
                        print(f"    [OK] {team_name}: Submitted successfully! ({score_str})")
                        total_submitted += 1
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

    print("\n" + "=" * 70)
    print("  Adviser Evaluation Summary")
    print("=" * 70)
    count_label = 'Evaluations Planned' if args.dry_run else 'Evaluations Created'
    print(f"  {count_label} : {total_submitted}")
    print(f"  Already Graded      : {total_skipped}")
    print(f"  Unavailable         : {total_unavailable}")
    print(f"  Evaluations Failed  : {total_failed}")
    print(f"  Account Failures    : {total_accounts_failed}")
    print("=" * 70)
    if total_failed or total_accounts_failed:
        print('[FAIL] Adviser evaluation run finished with errors. Check failures above; saved grades remain recorded.')
        print('    Rerunning skips recorded adviser grades. Writes are never retried automatically.')
        return 1
    if args.dry_run:
        print('[!] Dry-run complete. Run without --dry-run to submit the eligible missing grades.')
    elif total_submitted > 0:
        print("[OK] Adviser evaluations submitted! Refresh your browser to verify.")
    else:
        print('[OK] No new adviser grades were submitted. Check recorded grades and any skip reasons above.')
    return 0


if __name__ == "__main__":
    sys.exit(run())
