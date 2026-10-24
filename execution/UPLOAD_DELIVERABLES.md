# Upload sample deliverable files without chat

Run `upload_deliverables.py` yourself from the DefenSYS repository folder. It uses the normal API and does not need an AI subscription or API key. Start your DefenSYS backend first.

The script uploads distinct files for each team's PIT event or Capstone stage. It supports single files, named documents, concept-paper slots and multiple attachments. It reads the configured requirements and the selected teams' actual access state.

## Student batch uploads (recommended for demo data)

Use `--student-leaders` when preparing your plan. Like the evaluation automation, this trusted local mode scans the active cohort and makes ordinary API requests authenticated as each team's real student leader. The application records that student as **Uploaded by**, with the actual upload time. There is no admin upload followed by relabeling.

It reads your local Django configuration/database and creates short-lived student access tokens in memory. It never resets passwords, creates refresh-token records, changes team membership or grants new upload permissions. Run it from the same backend environment as your local demo. No new impersonation API is added to the application.

Keep **a folder for each team**, using the team's name from the selected event/stage. Inside, use the configured deliverable names:

```text
sample_file/UploadBatch/
  Team Phoenix/
    Concept Paper.pdf
    Pitch Deck.pptx
    Final Manuscript.pdf
  Team Atlas/
    Concept Paper.pdf
    Pitch Deck.pptx
    Final Manuscript.pdf
```

The team name is needed only on the folder, not on every filename. Each team's files are distinct. Matching uses names, never the order of teams/files. Case, spaces, underscores and punctuation are normalized; approximate spellings are not guessed. If selected teams have the same name, use their team-ID folders for those teams to avoid ambiguity. You run one command for the whole batch.

You can also keep any original filename by adding a deliverable folder:

```text
Team Phoenix/
  Concept Paper/
    Our project draft.pdf
  Final Manuscript/
    Approved copy.pdf
```

A single-file requirement's folder must contain just one file. Grouped requirements use their document-slot names inside the deliverable folder, for example `Concept Papers/Concept 1 - Concept paper.pdf` or `Final documents/Paper.pdf`. Multiple attachments can use their original filenames inside the deliverable folder. If a requirement name occurs in both pre/post lists, use `Team Phoenix/Pre/Concept Paper.pdf` and `Team Phoenix/Post/Concept Paper.pdf`.

```powershell
.\backend\venv\Scripts\python.exe execution/upload_deliverables.py prepare --student-leaders --scope pit --stage "System Concept Pitching" --all-teams --files-root "sample_file/UploadBatch" --manifest ".tmp/pit-student-uploads.json"
```

This discovers teams in that event's active-semester roster and maps their own files. For Capstone, use `--scope capstone --stage "Concept Proposal"`. You can narrow the scan with `--year "1st Year"` or use `--team-id 7 8 9` instead of `--all-teams`.

Preview the complete batch, then upload it:

```powershell
.\backend\venv\Scripts\python.exe execution/upload_deliverables.py run --manifest ".tmp/pit-student-uploads.json"
.\backend\venv\Scripts\python.exe execution/upload_deliverables.py run --manifest ".tmp/pit-student-uploads.json" --apply
```

The saved plan remembers student-leader mode and each uploader. No `--username` or student passwords are needed in this mode. Leaders must be active students and members of their teams. A changed leader requires a fresh plan so the uploader is checked again. The progress log records the student ID and username alongside each result.

If files are not ready yet, prepare the plan first to see the expected names, place the files, then prepare a new manifest filename or fill in the existing plan's `file` fields. The manifest includes `named_path` (team/deliverable names), `expected_path` (team IDs) and `flat_path` (one folder using IDs). Multiple matching files leave that mapping blank for you to resolve.

## Post-defense archive naming

Keep your local filenames as they are. For post-defense files, the script reads `suggested_file_name` from the existing API and sends that name through the normal upload's `file_name` and multipart filename fields, just as the student screen's Rename action does. No backend changes or new API parameters are needed. Archive-template variables are resolved by the existing API; the script preserves the actual uploaded extension, so a ZIP stays a ZIP even when a template ends in `.pdf`.

Preview displays the repository filename. Only the repository copy is renamed; no local files are moved or renamed. Named/concept documents and attachments receive a document identifier after the recommended base name so files in a group stay distinguishable. Pre-defense filenames remain unchanged.

## Alternative: sign in as one account

Use an administrator account to upload across demo teams, or a student account for its own teams. Faculty review authority alone does not grant file-upload permission. Passwords are prompted invisibly and never written to a file or changed.

Example for one PIT event, all teams visible to that account:

```powershell
.\backend\venv\Scripts\python.exe execution/upload_deliverables.py prepare --username YOUR_ADMIN_USERNAME --scope pit --stage "System Concept Pitching" --all-teams --files-root "sample_file/UploadBatch" --manifest ".tmp/pit-uploads.json"
```

Replace `YOUR_ADMIN_USERNAME` and the event name with your actual values. To select specific teams, replace `--all-teams` with `--team-id 7 8 9`. IDs must be the application's actual team IDs. Optional `--year "1st Year"` narrows the cohort.

For Capstone, use `--scope capstone --stage "Concept Proposal"`. The stage/event name must match exactly. The default server is `http://127.0.0.1:8000`; use `--base-url http://YOUR_SERVER:8000` during `prepare` if different.

Only pre-defense requirements are included by default. Use `--timing post` for post-defense files or `--timing all` for both. Upload windows and deadlines still apply. Signed minutes stay in the documenter signing workflow and are excluded. Shared section-system papers use their separate project-manager workflow; this script handles team deliverables.

The generated JSON records the server, active semester, scope, stage/event, project version, requirement IDs and exact document slots. It contains no credentials. Existing plans are never overwritten; choose a new manifest name when preparing again.

## 2. Place the files

Under `sample_file/UploadBatch`, use these folder patterns (example team ID `7`, requirement ID `D1`):

| Requirement | Team folder | One folder for the batch |
| --- | --- | --- |
| Single file | `7/D1.pdf` | `7__D1.pdf` |
| Named document with key `paper` | `7/D1/paper.pdf` | `7__D1__paper.pdf` |
| Concept slot `c1:paper` | `7/D1/c1__paper.pdf` | `7__D1__c1__paper.pdf` |
| Concept slot `c2:paper` | `7/D1/c2__paper.pdf` | `7__D1__c2__paper.pdf` |
| Multiple attachments | `7/D1/source.zip` | `7__D1__source.zip` |

`named_path`, `expected_path` and `flat_path` in each plan item show supported patterns. Windows-invalid slot characters in the ID layouts are represented by two underscores. IDs pin the final upload destination after name matching; sorting never determines the destination.

You have two choices:

- Place files first, then prepare the plan. Matching `file` paths are filled automatically. If several files match a single target, the script leaves it blank so you can choose.
- Prepare first to see the requirements, place your files, then either prepare a **new** plan filename or edit the existing plan's `file` fields. Paths are relative to `files_root`; use `/` separators in JSON, for example `"file": "7/D1.pdf"`.

Every team needs its own files. A plan that maps the same resolved file path to different teams is rejected. You can remove plan items you do not want to upload. For multiple attachments, place files before preparing, or copy the generated placeholder item and give each attachment a distinct `slot_key` and `file`. Keep the original team IDs, versions, uploaders and definition fingerprints.

Only files inside `files_root` are accepted. Blank mappings, missing files, empty files and incompatible extensions are reported. If you prepared an all-timing plan, later files may remain blocked until their workflow window opens.

## 3. Preview

```powershell
.\backend\venv\Scripts\python.exe execution/upload_deliverables.py run --username YOUR_ADMIN_USERNAME --manifest ".tmp/pit-uploads.json"
```

Preview performs no file uploads. It prints one result per target:

- `READY`: mapped file exists, format matches and the server currently permits uploading.
- `SKIP`: the target already has an upload; it is preserved, including approved or rejected files.
- `BLOCKED`: a mapping, permission, workflow, project-version or configuration issue needs attention.

In the alternative signed-in-account mode, `--username` uses the regular login endpoint, which can create normal login/token records even in preview. To avoid logging in repeatedly, you may supply an existing access token in the `DEFENSYS_UPLOAD_TOKEN` environment variable and omit `--username`. Tokens are never printed or saved by this tool. Expired tokens require signing in again. These login options are not used by student-leader plans.

## 4. Upload

```powershell
.\backend\venv\Scripts\python.exe execution/upload_deliverables.py run --username YOUR_ADMIN_USERNAME --manifest ".tmp/pit-uploads.json" --apply
```

Only `--apply` sends file uploads. It uploads ready targets and reports blocked ones separately. This is a per-file operation: if a later target fails, earlier successful files remain saved. Before every upload it refreshes server state, preserving files uploaded by a previous run. It never sends replacement file IDs, reviews files, endorses teams, submits evaluations, changes passwords, unlocks requirements or marks stages/events complete.

Rerun the same command after fixing a missing file or completing the prerequisite workflow. Successful/occupied slots are skipped. Multiple attachments use stable slot keys; existing filenames are also preserved rather than duplicated. New configurations, semesters or project versions require a newly prepared plan.

Every run appends results under `.tmp/<manifest-name>.upload-results.jsonl`. Each entry identifies the server, scope, term, stage/event, team, document slot, local file hash and outcome. You can choose another log with `--journal PATH`. The server remains the source of truth; deleting the log does not cause existing slots to be reuploaded.

An `.lock` file beside the manifest prevents simultaneous `--apply` runs for that same plan. A crashed process can leave it behind: verify the earlier process stopped, then delete that exact lock file before rerunning.

## If something fails

| Result | Next step |
| --- | --- |
| File not mapped/found | Fill `file` in the plan or place the file and prepare a new plan. |
| Existing upload skipped | Expected: this tool preserves uploads. Use the application's revision workflow to replace a file. |
| Permission or workflow lock | Check the signed-in account, endorsement state, defense date, upload deadline or post-defense availability in the app. |
| Requirement, semester or project changed | Prepare a new plan and review its targets. |
| HTTP 401 | Sign in again; the access token may have expired. |
| HTTP 403/400 | Read the reported API reason. Server validation remains authoritative. |
| HTTP 429 | Wait for the server's rate-limit window before another run. |
| Timeout/connection failure | A request may already have saved its file. Let the server finish, check the app/server log, then rerun to inspect current slots. Upload POSTs are never automatically retried. |

The tool prevents overlapping runs for one manifest, but cannot make a read followed by an upload atomic with another person's browser or a different manifest. Avoid uploading to the same slots concurrently. A `SKIP` preserves the existing file; it does not assert that its bytes match your sample or that it has been reviewed.

An HTTP 401 or 429 stops the batch and leaves the remaining targets unprocessed. Sign in again or wait for the rate-limit window, then rerun the same plan.

Exit codes: `0` = preview/apply finished without blocked targets; `1` = plan, login or startup error; `2` = one or more blocked targets; `130` = interrupted. Check the progress log for details. No manual database editing is needed to resume.

## Verify the script after changes

```powershell
.\backend\venv\Scripts\python.exe -m unittest execution.test_upload_deliverables -v
```

From the repository folder, run the script's real-endpoint integration tests on the isolated test database:

```powershell
.\backend\venv\Scripts\python.exe backend/manage.py test execution.test_upload_deliverables_api --pythonpath . --keepdb --noinput
```

The tests exercise real file bytes, grouped slots, permissions, preview and reruns. They do not upload to the demo database.
