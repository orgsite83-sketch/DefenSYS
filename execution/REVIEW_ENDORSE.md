# Review and endorse demo deliverables

`auto_review_endorse.py` simulates the application's faculty review actions using each team's actual assigned account. This is demo workflow automation, not an assessment of document quality. The default pre mode accepts eligible scheduling requirements and endorses the team through the existing API in one transaction. Post mode accepts/archive-reviews eligible uploaded post-defense files through the existing review API. No backend changes are needed.

Start the backend and run from `execution/`, with the backend virtual environment active:

```powershell
python auto_review_endorse.py --all-teams --year 1 --dry-run
```

This previews the active first-year PIT cohort. If exactly one event is configured for the selected year, it is selected automatically. Otherwise add its exact name with `--stage "System Concept Pitching"`.

To save the reviews and endorsements, run the same command without `--dry-run`:

```powershell
python auto_review_endorse.py --all-teams --year 1
```

For Capstone:

```powershell
python auto_review_endorse.py --all-teams --scope capstone --stage "Concept Proposal" --dry-run
```

## Post-defense acceptance and archiving

Add `--timing post` to accept eligible post-deliverables without endorsing the team again:

```powershell
python auto_review_endorse.py --all-teams --year 1 --timing post --dry-run
```

Remove `--dry-run` to save the approvals. To review only one post requirement, add its configured label or ID:

```powershell
python auto_review_endorse.py --all-teams --year 1 --timing post --deliverable D3 --dry-run
```

For Capstone add `--scope capstone --stage "Concept Proposal"`. Existing accepted files are preserved, including an accepted required paper when an optional attachment is still pending. Missing required files, incomplete document groups, rejected files, open correction requests and unavailable post-defense permissions remain blocked. Missing optional uploads are skipped. System-owned signed minutes retain their separate signing workflow.

Post mode refreshes the current faculty payload before each review, rechecks the requirement/file snapshot, and targets the exact current file ID. Accepted history is never reviewed again. Older primary-file records without version rows are rechecked against their original upload metadata and use the standard parent-review action. The post-review endpoint has no signed snapshot parameter; its existing permission/version checks remain authoritative. Each file is a separate API transaction, so an earlier successful approval remains saved if a later one fails. No POST is automatically retried.

An accepted post-file counts as archived in Deliverables. Public Project Archive visibility still follows the system's existing completion/publication rules. The review API can apply its normal progression/finalization or selected-concept revision updates when acceptance satisfies those rules. The script sends `clear_defense_revisions=false` and does not separately invoke revision clearance, grading, completion, publication or endorsement actions.

Use `--team-id 25 26` instead of `--all-teams` to select particular teams. `--base-url http://127.0.0.1:8000` can select another local/LAN backend that uses the same database configuration.

## Attribution and scope

- PIT uses the active section instructor assignment for that team's semester, year and section, in `workspace=instructor`.
- Capstone uses the team's active assigned adviser, in `workspace=adviser`. A Capstone section instructor is not a replacement for an adviser.
- Accounts use short-lived ordinary access tokens in memory. Passwords and refresh-token records are not changed. An admin/PIT Lead is never used as a fallback when an assignment is missing.
- If several instructors are assigned to the same team, the script reports ambiguity. Select an assigned username with `--reviewers USERNAME`, combined with `--team-id` if you only want that instructor's particular teams. This filter does not grant permissions.
- Reviewer identity, active semester and project version are revalidated before reads and writes. In pre mode, the backend's signed review token pins the requirements and uploaded-file snapshot. Post mode refreshes and checks each current file ID/revision and requirement before using the existing file-review endpoint.

## What the command does

- `READY`: the server permits the selected action; preview describes either scheduling review/endorsement or individual post-file acceptance.
- `ENDORSED`: the existing endpoint accepted the eligible files and endorsed the team using the assigned faculty actor. Existing accepted-file reviews are preserved.
- `ARCHIVED`: a post-file was accepted through the existing review API by the assigned faculty.
- `SKIP`: pre mode found an existing endorsement or no endorsement requirement; post mode found an accepted file, waived requirement or missing optional upload. An endorsed team can still have pending post-files processed in post mode. Current preparation for a repeat defense follows the server's current snapshot rather than skipping just because an earlier attempt was endorsed.
- `BLOCKED`: missing/incomplete files, rejected submissions, corrections, locked/scheduled/completed work, unavailable faculty assignments, stale context, or another server restriction needs attention.

Pre mode covers the **before-endorsement scheduling requirements** chosen by the server. Post mode covers the uploaded post-defense files currently eligible for faculty review. Neither mode separately reviews optional/defense-time pre-materials, selects concepts, schedules defenses, submits grades or invokes official event/stage completion. The script does not read document content to determine whether a paper deserves approval.

Runs append actor/outcome logs under the repository's `.tmp/`; tokens and credentials are never logged. Repeating a completed run skips endorsed teams. A failed/timed-out POST is not automatically retried; rerun to inspect current server state. HTTP 401/429 stops the batch. Exit codes are `0` for success/skips, `1` for setup errors, and `2` for blocked teams.

## Verification

From the repository root:

```powershell
.\backend\venv\Scripts\python.exe -m unittest execution.test_auto_review_endorse
.\backend\venv\Scripts\python.exe backend/manage.py test execution.test_auto_review_endorse_api --pythonpath . --keepdb --noinput
```

Integration fixtures use only Django's isolated test database and temporary media. Live demo invocations should use `--dry-run` until you intend to save the simulated approvals.
