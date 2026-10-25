# DefenSYS demo automation guide

Copy-and-paste PowerShell commands for uploading team files, faculty review and endorsement, panelist and peer evaluations, post-defense acceptance/archiving, adviser grading, and minutes drafts.

The first-year examples use **System Concept Pitching** and the existing sample files. These scripts simulate demo workflow actions through the application APIs. Generated grades and comments do not assess the quality of the actual work.

## 1. Start here

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

Each script authenticates and reads the live backend during a preview. The minutes script can initialize a draft when fetching it, even in preview; it skips saving generated comments until run without `--dry-run`.

## 2. Which script should I use?

| Task | Script | Account used |
| --- | --- | --- |
| Upload pre- or post-defense files | `execution/upload_deliverables.py` | Each team's student leader |
| Accept scheduling files and endorse teams | `execution/auto_review_endorse.py` | Assigned PIT instructor or Capstone adviser |
| Accept/archive uploaded post-defense files | `execution/auto_review_endorse.py --timing post` | Assigned PIT instructor or Capstone adviser |
| Generate panelist evaluations | `execution/auto_panelist_eval.py` | Assigned faculty and external panelists |
| Generate peer and self-evaluations | `execution/auto_peer_eval.py` | Students |
| Generate Capstone adviser grades | `execution/auto_adviser_eval.py` | Assigned advisers |
| Populate draft minutes comments | `execution/auto_documenter_minutes.py` | Assigned documenter |

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

Other peer options include `--students 4001 4002`, `--team-id 25`, `--session-id UUID`, `--semester-id 2`, and `--limit 5`. Default scores are 6-9 for a 10-point criterion; customize with `--min-score 7 --max-score 9`. The peer script has no `--scope` option.

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

Remove `--dry-run` to submit eligible missing adviser grades. Default scores are 7-9 for a 10-point criterion. Existing adviser grades are skipped. Availability comes from the API; adviser grading can open before the defense date when endorsement and scheduling requirements are satisfied.

Narrow the run with `--team-id 25`, `--advisers 208`, `--session-id UUID` or `--semester-id 2`. This script has no `--year` or `--scope` options. For Capstone uploads and faculty review, use the earlier commands with `--scope capstone` and the exact configured stage/requirement; PIT requirement IDs do not carry over automatically.

## 10. Documenter minutes drafts

Preview generated comments for one Capstone defense schedule:

```powershell
.\backend\venv\Scripts\python.exe execution\auto_documenter_minutes.py `
  --schedule-id 37 --dry-run
```

Replace `37` with the actual schedule ID. Remove `--dry-run` to save draft comments. Use `--all-minutes` instead of `--schedule-id 37` for the broad batch of eligible Capstone schedules, or filter with `--team-id 25` / `--documenter 211`.

Existing draft comments are kept unless `--overwrite` is supplied. Signed/submitted minutes are skipped. The script populates comments only; review, PDF preview, signatures and submission happen in the Documenter workspace. Fetching minutes can initialize their draft even in a preview. This script has no `--year`, `--stage` or `--scope` options.

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
