# PIT Flow Risk Brief

This note documents two PIT-specific risks found during the flow audit:

1. PIT schedule creation can rely too much on queryset visibility and not enough on serializer-level year-scope validation.
2. PIT peer evaluation can resolve the student's grade context by the latest PIT grade instead of an explicit PIT event.

These are related because PIT is event-based, while much of the older workflow was built around broad team/stage labels.

## Risk 1: PIT Scheduler Year Scope

### Cause

PIT lead visibility is scoped in shared queryset helpers such as `visible_schedules_for()` and `grade_records_for()`. That means normal list screens only show the PIT lead's assigned year.

The lower-level scheduler serializers, however, do not consistently enforce the PIT lead's assigned `pit_lead_year` when accepting create, generate-plan, or confirm-plan payloads. PIT scheduling validation mostly checks:

- the user is allowed to manage schedules,
- the schedule scope is PIT for PIT leads,
- the selected team is a PIT team,
- the event has a valid PIT grading config,
- duplicate schedules do not already exist for the same team/event.

The missing hard check is: "If this user is a PIT lead, the PIT team's `year_level` must equal the user's assigned `pit_lead_year`."

Relevant files:

- `backend/modules/defense/scheduler/serializers.py`
- `backend/modules/authentication_access_control/scopes.py`
- `backend/modules/student_teams/team_levels.py`

### Why This Is Dangerous

This is dangerous because queryset visibility protects what the UI normally displays, but it is not a complete write boundary.

If a crafted request submits a valid PIT team ID from another year, the serializer may accept it unless another layer blocks it. That can create several bad outcomes:

- A 2nd Year PIT lead could schedule a 1st Year or 3rd Year PIT team.
- A PIT event could be created with the right event name but wrong cohort.
- Grade rows could be created for teams outside the lead's academic scope.
- Repository upload windows and vault queues could later include records that should not belong to that PIT lead.
- Audit logs would show a valid user action, but the action would be semantically out of scope.

In short: the UI is scoped, but the write operation itself is not fully self-defending.

### Good Approach

Add one authoritative PIT scope guard and call it from all PIT schedule write paths.

Recommended shape:

```python
def assert_pit_team_in_user_scope(user, team):
    if not is_pit_lead_only(user):
        return
    pit_year = (user.pit_lead_year or '').strip()
    if not pit_year:
        raise ValidationError({'team_id': 'PIT lead year level is not configured.'})
    if not team.is_pit or team.year_level != pit_year:
        raise ValidationError({'team_id': 'Team is outside your PIT year scope.'})
```

Then use it in:

- single schedule create team resolution,
- generated plan team selection,
- confirm-plan slot validation,
- PIT event config writes if the event is meant to be year-specific.

Also add regression tests for:

- PIT lead cannot create a schedule for another PIT year.
- PIT lead cannot confirm a plan containing another PIT year.
- Admin can still schedule all valid PIT teams when admin behavior is intended.
- 3rd Year PIT remains blocked in 2nd Semester Capstone intake mode.

## Risk 2: PIT Peer Evaluation Uses Latest Grade

### Cause

PIT is event-based. A team can potentially have multiple PIT events in the same semester or across time.

The peer evaluation flow resolves the current student's grade through `GradeContextService.get_for_current_student_peer_context(team)`. For PIT teams, that resolver currently chooses the latest PIT `TeamGrade` for the team if one exists.

That is convenient, but it is implicit. The student peer-evaluation request does not clearly say which PIT event or `pit_event_config` the submission belongs to.

Relevant files:

- `backend/modules/grading/grades/peer_eval.py`
- `backend/modules/grading/grades/services.py`
- `backend/modules/grading/grades/models.py`
- `backend/modules/defense/scheduler/models.py`

### Why This Is Dangerous

This is dangerous when a PIT team has more than one event.

Example:

1. Team A is scheduled for "2nd Year PIT Expo".
2. A grade row is created.
3. Peer grading opens.
4. Later, another PIT event or corrected schedule creates a newer grade row.
5. A student submits peer evaluation.
6. The backend attaches the peer submission to the latest grade, not necessarily the intended event.

Possible outcomes:

- Peer evaluations land on the wrong PIT event.
- A correct event appears incomplete even though students submitted.
- A different event becomes complete because it received unrelated peer submissions.
- Official completion may block or pass the wrong event.
- Final grades and repository eligibility can be wrong.

This kind of bug is subtle because the data looks valid: the team exists, the student is a member, and the grade exists. The problem is identity, not basic validity.

### Good Approach

Make PIT peer evaluation event-specific.

Recommended API/data approach:

- Include `pit_event_config_id` or `team_grade_id` in peer-evaluation requests for PIT.
- Validate that the grade belongs to:
  - the requesting student's team,
  - scope `pit`,
  - the active semester or selected semester,
  - the intended `PitEventGradingConfig`,
  - an event where peer grading is currently open.
- For Capstone, continue resolving by the team's current stage if that remains the intended product behavior.

Safer resolver shape:

```python
def get_for_student_peer_context(team, *, pit_event_config_id=None, team_grade_id=None):
    if team.is_pit:
        if team_grade_id:
            return TeamGrade.objects.get(
                id=team_grade_id,
                team=team,
                scope=TeamGrade.SCOPE_PIT,
            )
        if pit_event_config_id:
            return TeamGrade.objects.get(
                team=team,
                scope=TeamGrade.SCOPE_PIT,
                pit_event_config_id=pit_event_config_id,
            )
        raise ValidationError({'pit_event_config_id': 'PIT peer evaluation requires an event context.'})
```

Frontend should pass the selected event or grade row from the PIT event currently open for peer grading.

Add regression tests for:

- peer submission attaches to the requested PIT event, not the latest grade,
- peer submission is rejected without event context when multiple PIT grades exist,
- peer submission is rejected when peer grading is closed for that event,
- Capstone peer evaluation still works for the current Capstone context.

## Implementation Priority

Fix scheduler year-scope enforcement first. It prevents new cross-year PIT schedules and keeps future data cleaner.

Then fix peer evaluation event identity. It prevents valid-looking submissions from being attached to the wrong event.

The broad design rule is:

> PIT writes should always carry an explicit PIT event identity, and PIT lead writes should always enforce the user's assigned PIT year at the write boundary.
