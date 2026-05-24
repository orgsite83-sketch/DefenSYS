# Peer evaluation notifications (deferred)

Peer evaluation integrity and admin visibility are implemented without push or in-app notifications. Use this backlog when adding alerts.

## Suggested triggers

- PIT Lead enables peer grading for an event (`notify_pit_peer_grading` already exists in `backend/modules/grading/grades/services.py`).
- Daily or periodic reminder while a team has incomplete peer submissions.
- Nudge when one evaluator finishes but teammates have not (`missing_evaluators` from `peer_completion_summary`).

## Implementation notes

- Reuse `realtime.broadcast` patterns (`notify_pit_peer_grading`).
- Deep-link students to the Peer Eval tab; deep-link PIT Lead / Admin to Grade Center event teams (filter incomplete).
- Do not auto-close events or compute `peer_score` until `is_team_peer_eval_complete` returns true (see `backend/modules/grading/grades/peer_eval.py`).
