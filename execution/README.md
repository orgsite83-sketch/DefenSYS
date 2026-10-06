# Execution (Layer 3)

Deterministic Python tools called from orchestration after reading a directive in `directives/`.

See [docs/AGENTS.md](../docs/AGENTS.md). Prefer extending existing scripts before adding new ones.

## Available Tools

- `start_local_web.py`: Launches local full-stack server (Django + Flutter Web) on LAN IP.
- `auto_peer_eval.py`: Automated testing tool to simulate student peer evaluations across teams and defense stages via REST API.
- `auto_panelist_eval.py`: Automated testing tool to simulate panelist evaluations for scheduled defenses via REST API.
- `auto_adviser_eval.py`: Automated testing tool to simulate capstone adviser grading for advised teams via REST API.

