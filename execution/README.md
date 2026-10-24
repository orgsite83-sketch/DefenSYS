# Execution (Layer 3)

Deterministic Python tools called from orchestration after reading a directive in `directives/`.

See [docs/AGENTS.md](../docs/AGENTS.md). Prefer extending existing scripts before adding new ones.

## Available Tools

- `start_local_web.py`: Launches Django + Flutter Web on a shared LAN/phone hotspot IP. Use `--check` for adapter/API/CORS diagnostics or `--interface "Wi-Fi"` to select an adapter. See [the network guide](../docs/WIFI_IP_CONFIG_GUIDE.md).
- `auto_peer_eval.py`: Automated testing tool to simulate student peer evaluations across teams and defense stages via REST API.
- `auto_panelist_eval.py`: Automated testing tool to simulate panelist evaluations for scheduled defenses via REST API.
- `auto_adviser_eval.py`: Automated testing tool to simulate capstone adviser grading for advised teams via REST API.
- `auto_documenter_minutes.py`: Automated testing tool to record realistic draft panelist comments for defense schedules requiring minutes via REST API.
- `upload_deliverables.py`: Scan each team's own PIT/Capstone files in one batch. Use team-name folders and deliverable names, such as `Team Phoenix/Concept Paper.pdf`. `prepare --student-leaders` uses read-only discovery and real student identities. Post files use the API's recommended archive naming. See [the upload guide](UPLOAD_DELIVERABLES.md). Existing files are preserved; no chat or AI API is needed.

### Panel evaluation automation

Configured concept hearings submit separate scores for every concept and each rubric target. The tool does not select the official concept: it leaves that decision and the recorded outcome to the chair after grading. Other Capstone verdict requests remain subject to the server's configured panel cutoff; adviser/peer scores cannot override it.

`auto_panelist_eval.py --all-panelists` includes faculty/admin panelists and assigned external invitations. `--panelists <usernames>` selects only those institutional accounts; `--external-only` selects only external invitations, and `--exclude-external` explicitly omits them. Existing evaluations are skipped.

Start with `backend/venv/Scripts/python.exe execution/auto_panelist_eval.py --external-only --scope pit --stage "PIT System Prototype Showcase" --dry-run`. Remove `--dry-run` to save simulated evaluations. `--stage` accepts a Capstone stage label or PIT event name. Discovery and API submissions share a schedule allowlist; without an explicit team, session, or semester, only the active semester is eligible.

External access uses normal scoped guest JWTs and guest API endpoints. Expired, revoked, or unapproved invitations are reported with a reason; the script does not renew access. Dry runs use GET requests only and do not create refresh-token records. Scores use a 0–10 range scaled to each criterion's maximum, including zero and fractional maxima. Exit codes: `0` completed, `1` failed request/configuration, `2` unavailable evaluations or pending verdicts. PIT events never receive Capstone verdicts.

