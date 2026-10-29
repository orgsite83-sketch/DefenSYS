# Panel evaluation automation

Use `auto_panelist_eval.py` from `execution/` with the same Python environment as the other automation scripts. The backend must be running. This generates demo scores through the existing panelist APIs, using the faculty and external evaluators actually assigned to each schedule.

## First-year PIT

Preview all assigned evaluations in the active semester:

```powershell
python auto_panelist_eval.py --all-panelists --scope pit --year 1 --dry-run
```

Save them:

```powershell
python auto_panelist_eval.py --all-panelists --scope pit --year 1
```

To limit the batch to one event, add its configured name:

```powershell
python auto_panelist_eval.py --all-panelists --scope pit --year 1 --stage "System Concept Pitching" --dry-run
```

`--year 1` is a cohort filter, not the event order. PIT events remain independent. Only assigned, currently scheduled defenses in the selected scope are considered. The script does not schedule defenses, advance to another event, or mark an event complete. Ordinary PIT evaluations save scores without Capstone verdicts; any required concept decision remains a separate chair action.

## Capstone

```powershell
python auto_panelist_eval.py --all-panelists --scope capstone --stage "Project Proposal" --dry-run
```

Remove `--dry-run` to save. By default, `--verdict auto` checks the assigned chair's refreshed API response after all selected evaluations. For a configured qualifying score, the API determines whether approval or re-defense is allowed, independently of adviser/peer weights. A low simulated panel score can therefore produce re-defense. For legacy hearings without a configured cutoff, `auto` requests approval only when the API allows the chair to issue a verdict.

Concept hearings submit the applicable per-concept or legacy rubric scores, then leave concept selection and the official outcome to the chair. The script never invents concept decisions or uses an administrator in place of a missing chair.

Useful options:

| Option | Behavior |
| --- | --- |
| `--no-verdict` | Submit scores only. |
| `--verdict-only` | Check existing evaluations and request ready Capstone verdicts without submitting scores. |
| `--verdict approved_with_revisions` | Request that outcome only if currently permitted. Add `--revision-deadline YYYY-MM-DD`, or use the default of 14 days from today in Manila. |
| `--panelists 208 215` | Only these assigned faculty/admin accounts; excludes external invitations. |
| `--external-only` | Only assigned external invitations. A ready Capstone verdict still uses its assigned faculty chair. |
| `--exclude-external` | Skip external invitations explicitly; missing required external scores keep the verdict pending. |
| `--team-id 25` | One team. |
| `--session-id UUID` | One scheduled session. |
| `--semester-id 2` | Explicit academic term. Otherwise use the active semester, except for explicit team/session selections. |
| `--min-score 8 --max-score 8` | Fixed 80% of each criterion maximum. Defaults are random 70–90%; zero and fractional maxima are supported. |
| `--include-drafts` | Preserve saved draft scores and remarks, fill missing scores, and submit the completed evaluation. |
| `--request-timeout 90` | Allow slower assignment responses or submissions up to 90 seconds. Defaults to 30 seconds; writes are never retried automatically. |

## Preserved workflow rules

- Existing submitted evaluations and verdicts are skipped. Saved drafts are skipped unless `--include-drafts` is supplied; intentional zero scores are preserved.
- If the selected cohort has no current scheduled defenses (including after they close), report a clean skip. If matching defenses exist but no selected active evaluators are assigned, report pending panel setup.
- Team, individual, and mixed rubrics cover every current criterion/member and every assessed concept when the hearing policy requires it.
- Before each live evaluation, refresh the assignment and send its current `evaluation_context`. Future dates, paused defenses, adviser conflicts, locked grades, changed assignments and other API blockers remain blocked.
- Local database discovery uses read-only transactions. In-memory access tokens do not change passwords, exchange invitation codes, renew external access, or insert refresh-token records. Use the backend's local database configuration and matching API server.
- No automatic retries of evaluation POSTs or verdict PATCHes. If a connection fails, rerun after checking the system; the earlier request may have saved. Authentication/rate-limit failures stop the remaining batch.
- Dry runs send GET requests only. A verdict preview reflects readiness **now**, so a preview can show planned scores and a pending verdict that will become available after a live run.
- Saving evaluations does not publish grades, accept archive files, sign minutes, clear concept decisions/revisions, or bypass completion requirements.

Exit codes: `0` finished, `1` request/configuration failure, `2` unavailable assignments or pending verdicts. A concept hearing can finish its automated scoring with exit `0` while its manual chair decision remains outstanding.

Local flow check (2026-10-29): faculty accounts assigned across multiple cohorts can take approximately 14 seconds to load assignments, exceeding the former hard-coded 10-second timeout. Use the configurable request timeout for both discovery and the mandatory refresh before each submission. After a timed-out write, inspect saved evaluations before rerunning.

## Verification

From the repository root:

```powershell
backend/venv/Scripts/python.exe -m unittest execution.test_eval_automation
backend/venv/Scripts/python.exe backend/manage.py test execution.test_panelist_eval_api grading.grades.test_external_panel_roster --pythonpath . --keepdb --noinput
```

The API regressions create fixtures only in Django's isolated test database. They cover real faculty/guest authentication, cutoff outcomes, incomplete panels, PIT scoring, private drafts, mixed targets, concept hearings and repeat-run preservation. No backend source changes are needed.
