# DefenSYS demo automation guide

For web/PWA and signed Android releases, installation links, version checks and
safe update prompts, use [App release guide](docs/APP_RELEASE_GUIDE.md).

For a full local backup and a fresh database to test the workflow yourself,
see [Local development setup](LOCAL_DEVELOPMENT.md). Sandbox commands use a
separate database and uploads folder.

Copy-and-paste PowerShell commands for uploading team files, faculty review and endorsement, panelist and peer evaluations, post-defense acceptance/archiving, adviser grading, and minutes drafts.

The first-year examples use **System Concept Pitching** and the existing sample files. These scripts simulate demo workflow actions through the application APIs. Generated grades and comments do not assess the quality of the actual work.

## 1. Start here

### PIT Concept Selection rollout

Normal PIT events keep their existing grading flow. Concept Selection events now
configure **Panel qualifying score** under **Grading & Rubrics**. The selected
concept supplies the team grade; a nonqualifying concept set requires another
hearing within that event. This does not create a prerequisite between PIT events.

Deploy the backend and rebuild/deploy the frontend together. No database schema
migration is needed: the cutoff is stored in the existing event concept settings.
Existing hearings retain their captured policy. To adopt an untouched hearing,
run `backend/manage.py adopt_pit_concept_flow --help` using the backend Python.
The command requires `--event-id` and `--qualifying-score`; its default is a
read-only preview. Get the event ID from the PIT event-config API response.

For existing hearings, preview the selected `--schedule-id` values, then repeat
the exact event, cutoff and schedule arguments with `--apply`, the returned
`--review-token`, and `--reason`. Re-run the preview whenever the selection changes.
The command refuses existing grades, submissions, drafts, recorded decisions,
historical/completed contexts and stale reviews. It audits configuration and
policy adoption without manufacturing scores or modifying uploaded files.
An event with no scheduled grades can also be configured through this preview/apply
flow without schedule IDs. Do not delete assessments to force eligibility.

  If an existing PIT concept hearing still shows one team rubric instead of
  separate concept assessments, inspect its saved policy first. From the server's
  `backend/` directory, run:

  ```bash
  python manage.py inspect_pit_concept_flow --team-name CodeSprint
  ```

  This report is read-only (PostgreSQL enforces a read-only transaction). It shows
  the event/schedule IDs, live cutoff, captured policy, concept keys, submission
  and draft counts, and initial adoption blockers without exposing draft contents.
  `single_team_score` with three captured concept keys explains why three files
  can appear beside only one rubric. A source deployment does not convert that
  saved hearing. `untouched_adoption_candidate` is a preliminary check; always
  use the adoption command's full preview and review token before applying.
  Existing scores/drafts cannot be copied across every concept: one team score
  does not identify which concept was assessed. Keep that evidence and review
  the transition rather than clearing it or guessing concept grades. A saved
  draft is not a submitted panel assessment and cannot unlock an outcome.

  For explicitly authorized test-draft replacement only, add `--replace-drafts`
  to BOTH preview and apply. The preview binds the exact draft contents and
  timestamps into its review token. Apply additionally requires `--draft-archive
  /private/new-file.json`; the command creates this file exclusively with private
  permissions before removing any drafts. Keep it outside publicly served paths.
  It still refuses submitted scores, prior attempts and recorded outcomes. A
  changed draft invalidates the preview. Panelists must close old editors before
  conversion and reload afterwards to enter fresh per-concept scores.

Run every command in this guide from the **DefenSYS project root**:

```powershell
Set-Location "C:\Users\Admin\Desktop\DefenSYS"
```

Start the backend in a separate terminal if it is not already running:

```powershell
.\backend\venv\Scripts\python.exe backend\manage.py runserver 0.0.0.0:8000
```

The commands use the backend virtual environment directly; activating it is optional. The default API address is `http://127.0.0.1:8000`. Use the backend that matches your local database configuration. Add `--base-url http://YOUR_SERVER:8000` when needed.

**Preview and save:** the simple commands below include `--dry-run`. Review the output, then run the same command without `--dry-run` to save that action. Explicit live commands are also provided for the post-defense upload and archive steps.

Previews inspect the configured local data and, where applicable, read the live backend. Minutes previews use read-only discovery and do not initialize drafts, save comments, apply signatures, or generate stored PDFs.

## 2. Which script should I use?

| Task | Script | Account used |
| --- | --- | --- |
| Upload pre- or post-defense files | `execution/upload_deliverables.py` | Each team's student leader |
| Accept scheduling files and endorse teams | `execution/auto_review_endorse.py` | Assigned PIT instructor or Capstone adviser |
| Accept/archive uploaded post-defense files | `execution/auto_review_endorse.py --timing post` | Assigned PIT instructor or Capstone adviser |
| Generate panelist evaluations | `execution/auto_panelist_eval.py` | Assigned faculty and external panelists |
| Generate peer and self-evaluations | `execution/auto_peer_eval.py` | Students |
| Generate Capstone adviser grades | `execution/auto_adviser_eval.py` | Assigned advisers |
| Populate draft minutes / complete signing | `execution/auto_documenter_minutes.py` / add `--sign-all` | Assigned documenter, assigned adviser, administrator |

For the first-year example, follow: **pre-upload -> faculty review/endorsement -> schedule in the UI -> panelist evaluation -> peer evaluation -> post-upload -> faculty acceptance/archive**. Record any required concept decision in the chair workspace. The backend determines when each step is available.

## 3. Upload pre-defense files

### All pre-defense requirements for first-year teams

```powershell
.\backend\venv\Scripts\python.exe execution\upload_deliverables.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --files "Defensys_sample files\sample_file\16_Teams_1st_Year\1st Sem" `
  --folder "D1=Concept Paper/PDF" `
  --dry-run
```

In this example configuration, D1 is the concept paper and D2 is the pitch deck. The explicit D1 folder mapping handles the configured label `Cocept Paper`; the `Pitch Deck` folder matches D2 automatically. Requirement IDs and labels belong to the selected event, so check them when switching events.

### Only the concept paper

```powershell
.\backend\venv\Scripts\python.exe execution\upload_deliverables.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --deliverable D1 `
  --files "Defensys_sample files\sample_file\16_Teams_1st_Year\1st Sem\Concept Paper\PDF" `
  --dry-run
```

Remove `--dry-run` to upload. The default timing is `pre`.

### How files match teams

For one selected deliverable, the folder can contain:

```text
AlphaWave_Concept_Paper.pdf
ApexCode_Concept_Paper.pdf
DevCraft_Concept_Paper.pdf
```

The filename's team prefix determines ownership. `AlphaWave` can match `Team AlphaWave`; sample numbering and the leading word `Team` are optional. The command's `--deliverable` selects the destination, not the filename suffix. The script reports ambiguous or missing matches and preserves existing files.

For grouped/concept requirements, use the configured document key or label with `--slot`, such as `--slot "c1:paper"`. Use distinct files for each team.

## 4. Faculty review and endorsement before defense

Configured Weekly Accomplishment Reports are submitted through the student
Deliverables collection after physical adviser signing. The generic upload script
skips this managed requirement. The assigned adviser must review and accept each
required week in DefenSYS; the review/endorsement script cannot accept weekly
reports automatically. Missing, pending, or correction-required weeks remain
endorsement blockers. Accepted late reports satisfy their week.

After uploading the required scheduling files:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_review_endorse.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --dry-run
```

Remove `--dry-run` to accept eligible scheduling files and endorse teams through their assigned instructors. This simulates acceptance; it does not inspect document quality. Missing/rejected files, corrections and workflow locks remain blockers.

If the script reports multiple assigned instructors, add `--reviewers USERNAME`, using the actual assigned account's username. An administrator is not used as a replacement for missing faculty assignments.

Schedule the defenses and assign panelists in the UI. These scripts do not create schedules. The defense date and current workflow state must permit grading.

## 5. Panelist evaluations

### First-year PIT

```powershell
.\backend\venv\Scripts\python.exe execution\auto_panelist_eval.py `
  --all-panelists --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --dry-run
```

Remove `--dry-run` to submit simulated evaluations. `--all-panelists` includes assigned faculty and external evaluators. Default generated scores are 70-90% of each criterion's maximum; add `--min-score 8 --max-score 8` for a fixed 80% in this panelist script.

Useful panelist options:

| Option | Purpose |
| --- | --- |
| `--team-id 25` | One team |
| `--panelists 208 215` | Only these assigned faculty usernames; excludes external invitations |
| `--external-only` | Only assigned external evaluators |
| `--exclude-external` | Omit external evaluators; missing required evaluations remain pending |
| `--include-drafts` | Keep draft scores/remarks, fill missing scores and submit |
| `--session-id UUID` | One scheduled session; replace UUID with its actual ID |
| `--semester-id 2` | One academic term |

Submitted evaluations are preserved; saved drafts are skipped by default. Future, paused or locked defenses remain blocked. PIT scoring does not issue Capstone verdicts. Required concept decisions remain a separate chair action.

### Capstone panelist scoring and verdicts

```powershell
.\backend\venv\Scripts\python.exe execution\auto_panelist_eval.py `
  --all-panelists --scope capstone `
  --stage "Project Proposal" `
  --dry-run
```

The default `--verdict auto` requests an allowed outcome through the assigned chair after evaluation. The backend's panel cutoff and readiness rules determine the result. Add `--no-verdict` for scoring only, or `--verdict-only` to check/request ready verdicts using already submitted scores. Concept hearings leave selection and the official concept outcome to the chair.

## 6. Peer evaluations

Run after every assigned faculty and external panelist has completed the current defense evaluation, on or after the defense date, with peer grading enabled and its rubric configured:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_peer_eval.py `
  --all-students --year 1 `
  --stage "System Concept Pitching" `
  --dry-run
```

Remove `--dry-run` to submit. Every student must rate themselves and every teammate using the same peer rubric. Self-ratings count equally with teammate ratings. The script skips already submitted evaluator/evaluatee pairs.

`--year` accepts `1`, `2`, `3`, `4` or labels such as `"1st Year"`. It filters student discovery and rechecks the dashboard team's cohort before scoring. It uses the team's assessment year, rather than the student's latest academic record. The script uses each student's currently selected dashboard evaluation context; `--stage` filters that context rather than switching stages.

Other peer options include `--students 4001 4002`, `--team-id 25`, `--session-id UUID`, `--semester-id 2`, and `--limit 5`. Default ratings are 6-9 out of 10, scaled proportionally to every criterion maximum; `--min-score 8 --max-score 10` produces 16-20/20 or 4-5/5. Scores retain up to two decimal places and support zero. The script sends raw scores with criterion IDs and sections so repeated names remain distinct; the backend applies the configured weights. The peer script has no `--scope` option.

For slower student dashboards, add `--request-timeout 90` (default: 30 seconds; maximum: 300). This applies to dashboard reads and submissions. A timed-out submission may already have saved; check the saved state before rerunning. The script does not automatically retry evaluation writes.

Peer automation rounds aggregate totals and maxima to two decimal places before sending JSON. Without that final rounding, adding valid decimal scores can produce a value such as `24.299999999999997`, which the API rejects with a decimal precision error. The summary lists failed evaluations and account failures and exits with status 1 when any fail; a dry run reports planned evaluations rather than saved records. After correcting a failure, rerun the same selection to fill missing evaluator/evaluatee pairs while preserving saved ratings. A team's peer score remains pending until every required self/teammate pair is recorded.

## 7. Upload the approved concept paper after defense

In the first-year example, **D3: Approved Concept Paper** is a post-defense requirement. Use the folder containing the final approved PDFs. The script maps filenames; it does not determine whether their contents are the approved versions.

Preview:

```powershell
.\backend\venv\Scripts\python.exe execution\upload_deliverables.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --timing post --deliverable "Approved Concept Paper" `
  --files "C:\Users\Admin\Desktop\DefenSYS\Defensys_sample files\sample_file\16_Teams_1st_Year\1st Sem\Concept Paper\PDF" `
  --dry-run
```

Upload:

```powershell
.\backend\venv\Scripts\python.exe execution\upload_deliverables.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --timing post --deliverable "Approved Concept Paper" `
  --files "C:\Users\Admin\Desktop\DefenSYS\Defensys_sample files\sample_file\16_Teams_1st_Year\1st Sem\Concept Paper\PDF"
```

`--deliverable D3` selects the same requirement in this configuration. `--timing post` is essential because uploads otherwise default to pre-defense requirements. Uploads use the actual student leaders, preserve occupied targets, and follow normal upload permissions/deadlines.

The repository copy uses the API's configured archive filename. Local files keep their original names. Uploading alone leaves faculty acceptance pending.

## 8. Accept and archive the uploaded papers

Use the faculty review script in **post** mode. This reviews files already uploaded to the server; it does not need a local `--files` path.

Preview D3 acceptance/archiving:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_review_endorse.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --timing post --deliverable D3 `
  --dry-run
```

Save the acceptance/archiving:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_review_endorse.py `
  --all-teams --scope pit --year 1 `
  --stage "System Concept Pitching" `
  --timing post --deliverable D3
```

The assigned PIT instructor accepts each eligible current file. Successful results show `ARCHIVED`; accepted files are skipped on a repeat run. Omit `--deliverable D3` to process all eligible post-defense requirements for the selected event.

**Deliverables archive and public Project Archive:** an accepted post-file counts as archived in Deliverables. Public Project Archive visibility still follows the application's completion/publication rules. Acceptance can trigger the review API's normal progression or finalization behavior when its conditions are satisfied. The script does not separately invoke grade publication, revision clearance or official completion. Post mode does not endorse teams again.

Missing/incomplete/rejected files, open corrections, unavailable reviewers and workflow restrictions remain blocked. Required concept decisions and signed minutes retain their own workflows.

## 9. Capstone adviser evaluations

This script is for assigned Capstone advisers:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_adviser_eval.py `
  --all-advisers --stage "Project Proposal" `
  --dry-run
```

Remove `--dry-run` to submit eligible missing adviser grades. Default ratings are 7-9 out of 10, scaled proportionally to each criterion maximum: 8-10 generates 16-20/20 or 4-5/5. Zero and decimal ratings are preserved. The script sends raw scores with criterion IDs and sections; the backend applies the configured weights for team, individual, and mixed rubrics. Existing adviser grades, including zero, are skipped. Availability comes from the API; adviser grading can open before the defense date when endorsement and scheduling requirements are satisfied.

Add `--request-timeout 90` for slower grade lists or submissions (default: 30 seconds; maximum: 300). The summary distinguishes planned dry-run evaluations, recorded grades, unavailable grading, submission failures, and account failures. Failures produce exit status 1; authentication/rate-limit responses stop the remaining batch. Timed-out writes are never retried automatically and may already have saved. Check recorded grades before rerunning; the script skips grades already visible in the adviser list. API regressions in `grading.grades.test_weighted_scoring` verify real adviser authentication, repeated names across sections, weighted results for all three targets, and preservation on repeat runs.

Narrow the run with `--team-id 25`, `--advisers 208`, `--session-id UUID` or `--semester-id 2`. This script has no `--year` or `--scope` options. For Capstone uploads and faculty review, use the earlier commands with `--scope capstone` and the exact configured stage/requirement; PIT requirement IDs do not carry over automatically.

## 10. Documenter minutes and signatures

Preview generated comments for one Capstone defense schedule:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_documenter_minutes.py `
  --schedule-id 37 --dry-run
```

Replace `37` with the actual schedule ID. Remove `--dry-run` to save draft comments. Use `--all-minutes` instead of `--schedule-id 37` for the broad batch of eligible Capstone schedules, or filter with `--team-id 25` / `--documenter 211`.

Existing draft comments are kept unless `--overwrite` is supplied. The default action fills draft comments only. Discovery defaults to the active semester and current project version; use `--stage`, `--semester-id`, or `--session-id` to narrow it. Future, paused, cancelled and stale assessments are not processed. This script has no `--year` or `--scope` options.

To complete the normal documenter, adviser and administrator acceptance/signature flow using their existing uploaded signatures:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_documenter_minutes.py `
  --all-minutes --stage "Project Proposal" --semester-id 3 `
  --sign-all --admin admin --dry-run
```

Replace the term ID and administrator username with the intended values. Remove `--dry-run` to fill missing draft comments, preview each signing step, submit as the assigned documenter, sign as the team's adviser, then sign as the administrator and verify the official PDF. Without `--admin`, the schedule's active administrator creator is selected, or the sole administrator with a signature when unambiguous. Missing accounts/signatures block the record before draft creation. The assigned adviser must also have the Adviser duty enabled, matching the signing API; both preview and live `--sign-all` check this before starting. Draft-comment-only mode does not require adviser signing permissions or signatures. The script never uploads or changes signatures/passwords.

Partially signed minutes resume at the next required signature. Completed minutes are preserved, including when `--overwrite` is supplied. The summary retains acknowledged comment saves and signatures when a later step fails. No write is retried automatically; after a timeout, inspect saved state before rerunning. `--request-timeout 90` allows slower PDF responses. Exit code `1` reports blocked/failed records; `0` means all selected actions finished or existing completed records were preserved. Generated comments remain simulated demo feedback. Verify with `python backend/manage.py test execution.test_documenter_minutes --pythonpath . --keepdb --noinput` from the repository root, using the backend virtual environment and isolated test database.

## 11. Filters and common problems

| Need or result | What to do |
| --- | --- |
| Another year | Upload, review, panelist and peer scripts accept `--year 2` or `--year "2nd Year"`. Adviser/minutes scripts do not. |
| Selected teams | Upload/review accept `--team-id 25 26` instead of `--all-teams`. Panelist/peer/adviser/minutes accept a single `--team-id 25`. |
| Multiple events configured | Supply the exact `--stage` name. Upload/review can auto-select only when one event/stage is available. |
| `READY` | The preview found an action currently permitted by the backend. Run without `--dry-run` to save. |
| `SKIP` / already completed | The script preserved an existing file, review or evaluation, or found no applicable work. Read the reason. |
| Peer evaluation unavailable | Finish all current panel evaluations and check the defense date, peer-access switch, rubric and grade locks. |
| No matching files | Check the selected folder, full team-name prefixes, requirement ID/label and grouped document slot. |
| Post upload blocked | Check that the outcome/concept decision and current upload permissions permit the post requirement. |
| Multiple assigned instructors | Resolve the review selection with `--reviewers USERNAME` for an actually assigned account. |
| No reviewers/panelists/documenter | Configure the required assignment in the application. |
| `BLOCKED`, rejected files or open corrections | Resolve the stated workflow requirement, then preview again. |
| Accepted file absent from public Project Archive | Check the normal completion, archive configuration and publication requirements in the UI. |
| Connection/authentication/rate-limit failure | Check the server and current saved state before rerunning; a request may already have saved. |

Upload and faculty review scripts append local result logs under `.tmp/`. Preview reports current readiness; a later live run can encounter changed files, assignments or locks.

## 12. Detailed references and help

- [Upload guide](execution/UPLOAD_DELIVERABLES.md): folder layouts, document slots, archive filenames and advanced saved plans.
- [Faculty review guide](execution/REVIEW_ENDORSE.md): endorsement, post-file acceptance, reviewer scope and blockers.
- [Panelist guide](execution/PANELIST_EVALUATION.md): external evaluators, drafts, cutoffs, concepts and verdicts.
- [Execution tool index](execution/README.md).

The advanced upload workflow uses `prepare` / `run`: `run` previews by default, and `run --apply` uploads. The simple upload commands in this guide save by default and use `--dry-run` for previews.

To inspect a script's current options, replace the filename in:

```powershell
.\backend\venv\Scripts\python.exe execution\upload_deliverables.py --help
```
