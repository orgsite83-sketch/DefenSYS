"""
Automate Documenter Minutes of Defense Comments over HTTP REST API.

Simulates documenters recording realistic panelist comments for Capstone defense schedules
via the actual DefenSYS backend API endpoints:
  - Discovers schedules requiring minutes: stage.minutes_required=True or assigned documenter
  - Initializes / retrieves minutes draft: GET /api/defense/minutes/<schedule_id>/
  - Generates realistic, constructive panelist comments tailored by role (Chair, Technical, UI/UX)
  - Saves comments as draft: PATCH /api/defense/minutes/<schedule_id>/

Note:
  This script specifically focuses on what the Documenter fills in their workspace (draft comments).
  It does NOT submit or apply e-signatures, allowing you to review, sign, and submit directly
  in the Documenter workspace UI.

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
"""

import argparse
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


def parse_args():
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
        help="Preview  erated comments without updating the server",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.1,
        help="Delay in seconds between requests (default: 0.1s)",
    )
    return parser.parse_args()


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


def fetch_eligible_schedules(
    team_id: Optional[int] = None,
    schedule_id: Optional[int] = None,
    documenter_username: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """
    Finds Capstone defense schedules that require minutes or have a documenter assigned.
    Safe read-only query against the database.
    """
    init_django()
    from defense.scheduler.models import DefenseSchedule  # type: ignore

    qs = (
        DefenseSchedule.objects.filter(scope=DefenseSchedule.SCOPE_CAPSTONE)
        .exclude(status=DefenseSchedule.STATUS_CANCELLED)
        .select_related("team", "defense_stage", "documenter")
        .prefetch_related("panel_assignments__panelist")
        .order_by("scheduled_date", "start_time", "pk")
    )

    if schedule_id:
        qs = qs.filter(pk=schedule_id)
    if team_id:
        qs = qs.filter(team_id=team_id)
    if documenter_username:
        qs = qs.filter(documenter__username=documenter_username)

    results = []
    for sched in qs:
        # Check if minutes are required for this schedule or stage
        if not (sched.requires_minutes or sched.documenter_id):
            continue

        results.append({
            "id": sched.id,
            "team_id": sched.team_id,
            "team_name": sched.team.name if sched.team else f"Team #{sched.team_id}",
            "stage_label": sched.defense_stage.label if sched.defense_stage else "Defense",
            "minutes_required": sched.requires_minutes,
            "documenter_id": sched.documenter_id,
            "documenter_username": sched.documenter.username if sched.documenter else None,
            "documenter_name": sched.documenter.get_full_name() if sched.documenter else "Unassigned",
        })

    return results


def run():
    args = parse_args()

    if not args.all_minutes and not args.team_id and not args.schedule_id and not args.documenter:
        print("[!] Error: Specify --all-minutes, --team-id <id>, --schedule-id <id>, or --documenter <username>.")
        sys.exit(1)

    print("[*] Discovering defense schedules requiring minutes...")
    schedules = fetch_eligible_schedules(
        team_id=args.team_id,
        schedule_id=args.schedule_id,
        documenter_username=args.documenter,
    )

    if not schedules:
        print("[!] No eligible defense schedules requiring minutes found.")
        sys.exit(1)

    print("=" * 70)
    print("  DefenSYS Documenter Minutes Automation (Comments Only)")
    print("=" * 70)
    print(f"  Target Server   : {args.base_url}")
    print(f"  Total Schedules : {len(schedules)}")
    print(f"  Overwrite Mode  : {'YES (replace existing comments)' if args.overwrite else 'NO (preserve existing comments)'}")
    print(f"  Mode            : {'DRY RUN (Preview only, no changes saved)' if args.dry_run else 'LIVE DRAFT UPDATE'}")
    print("=" * 70)

    # Cache tokens by documenter username
    doc_tokens: Dict[str, str] = {}

    total_processed = 0
    total_skipped = 0
    total_comments_saved = 0

    for sched in schedules:
        sched_id = sched["id"]
        team_name = sched["team_name"]
        stage_label = sched["stage_label"]
        doc_username = sched["documenter_username"]
        doc_name = sched["documenter_name"]

        print(f"\n[*] Schedule #{sched_id} | {team_name} ({stage_label})")

        if not doc_username:
            print(f"  [SKIP] No documenter assigned to schedule #{sched_id}.")
            total_skipped += 1
            continue

        # Get JWT token for documenter
        if doc_username not in doc_tokens:
            token = get_jwt_token_for_user(doc_username)
            if not token:
                print(f"  [FAIL] Cannot authenticate documenter {doc_username}.")
                total_skipped += 1
                continue
            doc_tokens[doc_username] = token

        token = doc_tokens[doc_username]
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        # Step 1: Fetch minutes detail (also auto-creates draft if not yet initialized)
        detail_url = f"{args.base_url.rstrip('/')}/api/defense/minutes/{sched_id}/"
        try:
            res = requests.get(detail_url, headers=headers, timeout=10)
        except Exception as e:
            print(f"  [FAIL] Network error fetching minutes for schedule #{sched_id}: {e}")
            total_skipped += 1
            continue

        if res.status_code != 200:
            print(f"  [FAIL] Failed to fetch minutes (HTTP {res.status_code}): {res.text}")
            total_skipped += 1
            continue

        minutes_data = res.json()
        current_status = minutes_data.get("status", "draft")

        # Check status: if already submitted, adviser signed, or completed
        if current_status != "draft":
            print(f"  [SKIP] Minutes already signed or submitted (Status: '{current_status}').")
            total_skipped += 1
            continue

        panelist_comments = minutes_data.get("panelist_comments", [])
        if not panelist_comments:
            print("  [SKIP] No panelist comment slots found on minutes record.")
            total_skipped += 1
            continue

        # Check if comments need to be updated
        comments_to_update = []
        for c in panelist_comments:
            c_id = c["id"]
            role_snapshot = c.get("panelist_role_snapshot", "Panel Member")
            name_snapshot = c.get("panelist_name_snapshot", "Panelist")
            existing_comment = (c.get("comments") or "").strip()
            display_order = c.get("display_order", 0)

            if existing_comment and not args.overwrite:
                print(f"  [KEEP] {role_snapshot} ({name_snapshot}): Comment already recorded.")
                continue

            new_comment_text = generate_panelist_comment(role_snapshot, display_order)
            comments_to_update.append({
                "id": c_id,
                "role": role_snapshot,
                "name": name_snapshot,
                "text": new_comment_text,
            })

        if not comments_to_update:
            print("  [SKIP] All panelist comments are already filled. (Use --overwrite to replace them).")
            total_skipped += 1
            continue

        print(f"  [INFO] Documenter: {doc_name} ({doc_username}) | Generating {len(comments_to_update)} comment(s):")
        for item in comments_to_update:
            short_preview = item["text"][:80] + ("..." if len(item["text"]) > 80 else "")
            print(f"    - {item['role']} ({item['name']}): \"{short_preview}\"")

        if args.dry_run:
            print("  [OK] [DRY RUN] Comments previewed successfully.")
            total_processed += 1
            total_comments_saved += len(comments_to_update)
            continue

        # Step 2: PATCH comments to save draft
        patch_payload = {
            "comments": [
                {"id": item["id"], "comments": item["text"]}
                for item in comments_to_update
            ]
        }

        try:
            patch_res = requests.patch(detail_url, headers=headers, json=patch_payload, timeout=10)
        except Exception as e:
            print(f"  [FAIL] Network error saving draft comments: {e}")
            total_skipped += 1
            continue

        if patch_res.status_code == 200:
            print(f"  [OK] Saved {len(comments_to_update)} panelist comment(s) in draft.")
            total_processed += 1
            total_comments_saved += len(comments_to_update)
        else:
            print(f"  [FAIL] Failed to save comments (HTTP {patch_res.status_code}): {patch_res.text}")
            total_skipped += 1

        if args.delay > 0:
            time.sleep(args.delay)

    print("\n" + "=" * 70)
    print("  SUMMARY")
    print("=" * 70)
    print(f"  Total Schedules Processed : {total_processed}")
    print(f"  Total Comments Saved       : {total_comments_saved}")
    print(f"  Total Schedules Skipped   : {total_skipped}")
    print("=" * 70)
    print("[*] Minutes drafts are now populated with panelist comments.")
    print("[*] You can now open the Documenter workspace in the web app, review the comments,")
    print("    preview the PDF, sign with your e-signature, and submit whenever you are ready!\n")


if __name__ == "__main__":
    run()
