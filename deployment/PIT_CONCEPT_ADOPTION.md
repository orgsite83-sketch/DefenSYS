# Convert CodeSprint's authorized test hearing

Reviewed target: PIT event 2, schedule 5, grade 5, Team CodeSprint (team 7).
The user approved replacing the single private draft and selected a 75% cutoff.
The server report showed three concepts and zero submitted evaluations/results.
Run this only against that same server. It does not copy the old 8/10 to any
concept. It archives the old draft and requires new per-concept evaluations.

Ask panelists to close this hearing's grading screen before applying the change.
Keep the archive private. The tool refuses changed previews, submitted grades,
historical/completed hearings and existing archive paths.

## Laptop PowerShell

```powershell
cd C:\Users\Admin\Desktop\DefenSYS
scp .tmp\pit-concept-adoption.tar.gz defensys@74.113.234.178:~/
```

## Server SSH

```bash
cd /opt/defensys
tar -xzf ~/pit-concept-adoption.tar.gz
cd backend
source venv/bin/activate
```

Preview and save the review token (no database changes):

```bash
python manage.py adopt_pit_concept_flow --event-id 2 --schedule-id 5 --qualifying-score 75 --replace-drafts > ~/pit-concept-preview.json
cat ~/pit-concept-preview.json
```

Continue only if schedule 5 is the sole hearing and `eligible` is `true`.
Apply the exact preview; Bash reads its token directly from the saved JSON:

```bash
python manage.py adopt_pit_concept_flow --event-id 2 --schedule-id 5 --qualifying-score 75 --replace-drafts --apply --review-token "$(python -c 'import json,pathlib; print(json.loads((pathlib.Path.home()/"pit-concept-preview.json").read_text())["review_token"])')" --draft-archive "$HOME/deploy-backups/codesprint-draft-$(date +%Y%m%d_%H%M%S).json" --reason "User authorized replacing CodeSprint test draft and adopting 75 percent per-concept grading"
python manage.py inspect_pit_concept_flow --schedule-id 5
```

The result should show `adopted_count: 1`. Inspection should show cutoff 75,
`per_concept: true`, `automatic_outcomes: true`, and `draft_count: 0`. Keep the
archive. If any command fails, stop and read its error rather than clearing data.

Reload the grading workspace on the current deployed frontend. Assess c1, c2
and c3 separately and submit all required panel evaluations. Exactly one
qualifying concept is selected automatically; multiple qualifying concepts need
the chair's choice; none qualifying requires another concept hearing. This
changes event 2's cutoff for future schedules while converting only schedule 5.
