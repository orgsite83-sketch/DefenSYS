# Dynamic Grade Composition Plan

## Purpose

The client request is:

- Capstone grade categories should be dynamic and editable.
- PIT grade categories should be dynamic and editable.
- Current examples:
  - Capstone: Panel, Peer, Adviser
  - PIT: Panel, Peer

This plan explains how to make that work without breaking rubrics, grading, peer evaluation, grade center, reports, and repository readiness.

## Important Distinction

Rubrics and grade categories are connected, but they should not be the same source of truth.

Rubrics answer:

- What criteria/questions are scored?
- What scale does each criterion use?
- Which evaluation workflow does this rubric belong to?

Grade composition answers:

- Which score categories count toward the final grade?
- What percentage does each category contribute?
- Is a category required before publishing?
- Which rubric is assigned to that category for this stage or event?

Example:

- "Panel" is a grade category worth 50%.
- "Concept Hearing Panel Rubric" is the scoring form used to produce the Panel score.

If we treat rubrics as the category source of truth, adding/removing categories becomes dangerous because rubrics can be duplicated, renamed, drafted, unpublished, or replaced. The composition should own the category list and weights. Rubrics should be assigned to categories.

## Current System State

### Capstone

Capstone composition currently lives in:

- `StageGradingConfig`

Current fixed fields:

- `panel_weight`
- `adviser_weight`
- `peer_weight`
- `panel_rubric`
- `adviser_rubric`
- `peer_rubric`

The config is per:

- defense stage
- semester

This is already partially dynamic because admins can edit the percentages per stage/semester. The limitation is that the category set is fixed to Panel, Adviser, Peer.

### PIT

PIT composition currently lives in:

- `PitEventGradingConfig`

Current fixed fields:

- `panel_weight`
- `peer_weight`
- `panel_rubric`
- `peer_rubric`

The config is per:

- semester
- PIT event name

This is also partially dynamic because PIT Lead can edit Panel/Peer percentages per event. The limitation is that the category set is fixed to Panel and Peer.

### Team Grade Snapshot

Actual grade records live in:

- `TeamGrade`

Current fixed score/weight fields:

- `panel_score`
- `adviser_score`
- `peer_score`
- `panel_weight`
- `adviser_weight`
- `peer_weight`

This is important. Once a schedule or grade exists, the grade should snapshot the composition used at that time. Otherwise, editing stage/event composition later could silently change historical grades.

### Grade Breakdown

Rubric criterion scores live in:

- `GradeBreakdown`

Current type field:

- `evaluation_type = panel | adviser | peer`

This means the system already stores criterion-level breakdown by category type, but only for the three built-in types.

## Why "Just Add A New Category" Is Not Simple

Panel, Adviser, and Peer are not only labels. They each map to different workflows.

Panel:

- submitted by panelists
- connected to schedule panel assignments
- uses panel rubric
- contributes to panel score

Adviser:

- submitted by adviser
- Capstone only right now
- uses adviser rubric
- contributes to adviser score

Peer:

- submitted by students
- depends on peer evaluation windows and completion checks
- uses peer rubric
- contributes to peer score

So if the client says "add another category", we must also ask:

- Who submits it?
- Which screen submits it?
- Is it required?
- Does it use a rubric?
- Does it require one submission, many panelist submissions, adviser submission, or student peer submissions?
- Can it be enabled for PIT, Capstone, or both?

Without those answers, arbitrary categories would create records that have weight but no real workflow to produce the score.

## Recommended Product Interpretation

For the next change, interpret "dynamic" as:

1. Admin/PIT Lead can edit visible grade composition rows.
2. Categories can be enabled/disabled where the workflow already exists.
3. Weights are editable and must total 100%.
4. Rubrics are assigned per category.
5. The UI displays composition as rows instead of fixed Panel/Adviser/Peer input boxes.

That gives the client what they are likely asking for visually and operationally, while avoiding a risky new custom-grading engine.

After that works, we can support truly custom categories as Phase 2.

## Proposed Data Model

### Phase 1: Normalize Existing Built-In Categories

Add component rows while preserving current columns for compatibility.

New model:

```text
GradeCompositionComponent
```

Fields:

- `scope`: `capstone` or `pit`
- `stage_grading_config`: nullable FK to `StageGradingConfig`
- `pit_event_config`: nullable FK to `PitEventGradingConfig`
- `component_type`: `panel`, `adviser`, or `peer`
- `label`: display label, default `Panel`, `Adviser`, `Peer`
- `weight`: 0-100
- `rubric`: nullable FK to `Rubric`
- `is_enabled`: boolean
- `is_required`: boolean
- `display_order`: integer
- `created_at`, `updated_at`

Constraints:

- Capstone component must belong to one `StageGradingConfig`.
- PIT component must belong to one `PitEventGradingConfig`.
- Only one component of each `component_type` per config.
- Enabled component weights must total 100%.
- PIT cannot enable adviser unless the system later adds an adviser workflow for PIT.

Default rows:

Capstone:

- Panel, 50, enabled, required
- Adviser, 30, enabled, required
- Peer, 20, enabled, required/controlled by peer setting

PIT:

- Panel, 80, enabled, required
- Peer, 20, enabled, required/controlled by peer setting

### Phase 1 Compatibility

Keep these existing fields:

- `StageGradingConfig.panel_weight`
- `StageGradingConfig.adviser_weight`
- `StageGradingConfig.peer_weight`
- `StageGradingConfig.panel_rubric`
- `StageGradingConfig.adviser_rubric`
- `StageGradingConfig.peer_rubric`
- `PitEventGradingConfig.panel_weight`
- `PitEventGradingConfig.peer_weight`
- `TeamGrade.panel_score`
- `TeamGrade.adviser_score`
- `TeamGrade.peer_score`
- `TeamGrade.panel_weight`
- `TeamGrade.adviser_weight`
- `TeamGrade.peer_weight`

Reason:

- Many serializers, reports, dashboards, readiness checks, and grade calculations still read those fields.
- Removing them now would create a large blast radius.

Instead, component rows become the new source of truth for composition editing, then we mirror built-in component values back to existing columns.

## Proposed API Shape

### Capstone Stage Config

Existing endpoint:

```text
GET/PATCH /api/defense/stages/<stage_id>/grading-config/
```

Add to response:

```json
{
  "components": [
    {
      "id": 1,
      "component_type": "panel",
      "label": "Panel",
      "weight": 50,
      "rubric_id": 10,
      "rubric_name": "Concept Hearing Panel Rubric",
      "is_enabled": true,
      "is_required": true,
      "display_order": 1
    },
    {
      "id": 2,
      "component_type": "adviser",
      "label": "Adviser",
      "weight": 30,
      "rubric_id": 11,
      "rubric_name": "Concept Hearing Adviser Rubric",
      "is_enabled": true,
      "is_required": true,
      "display_order": 2
    },
    {
      "id": 3,
      "component_type": "peer",
      "label": "Peer",
      "weight": 20,
      "rubric_id": 12,
      "rubric_name": "Concept Hearing Peer Rubric",
      "is_enabled": true,
      "is_required": true,
      "display_order": 3
    }
  ]
}
```

Allow PATCH with:

```json
{
  "components": [
    {
      "component_type": "panel",
      "label": "Panel",
      "weight": 60,
      "rubric_id": 10,
      "is_enabled": true,
      "is_required": true,
      "display_order": 1
    },
    {
      "component_type": "adviser",
      "label": "Adviser",
      "weight": 0,
      "rubric_id": null,
      "is_enabled": false,
      "is_required": false,
      "display_order": 2
    },
    {
      "component_type": "peer",
      "label": "Peer",
      "weight": 40,
      "rubric_id": 12,
      "is_enabled": true,
      "is_required": true,
      "display_order": 3
    }
  ]
}
```

Validation:

- Enabled weights must total 100%.
- Disabled components must have weight 0.
- Component rubric must match scope and component type.
- Capstone panel category requires a panel rubric before scheduling.
- Capstone adviser category requires an adviser rubric only if adviser is enabled and required.
- Capstone peer category requires a peer rubric only if peer is enabled and required.

### PIT Event Config

Existing endpoint:

```text
GET/POST /api/defense/schedules/pit-event-config/
```

Add to response:

```json
{
  "components": [
    {
      "component_type": "panel",
      "label": "Panel",
      "weight": 80,
      "rubric_id": 20,
      "rubric_name": "PIT Panel Rubric",
      "is_enabled": true,
      "is_required": true,
      "display_order": 1
    },
    {
      "component_type": "peer",
      "label": "Peer",
      "weight": 20,
      "rubric_id": 21,
      "rubric_name": "PIT Peer Rubric",
      "is_enabled": true,
      "is_required": true,
      "display_order": 2
    }
  ]
}
```

Validation:

- Enabled PIT weights must total 100%.
- PIT adviser is not allowed in Phase 1.
- PIT panel component must use a PIT panel rubric.
- PIT peer component must use a PIT peer rubric.

## UI Plan

### Defense Stages Screen

Replace fixed inputs:

- Panel %
- Adviser %
- Peer %

With a composition table:

| Enabled | Category | Weight | Rubric | Required |
| --- | --- | --- | --- | --- |
| yes/no | Panel | number | Panel rubric select | yes/no |
| yes/no | Adviser | number | Adviser rubric select | yes/no |
| yes/no | Peer | number | Peer rubric select | yes/no |

Rules:

- Total enabled weight must show live and must equal 100%.
- Disabled row automatically becomes weight 0.
- For Capstone, Adviser row can be disabled if client wants a stage without adviser grade.
- Existing reset button becomes "Reset default composition".

### Defense Scheduler Screen

Capstone:

- Stage selection loads stage composition.
- Rubric fields are generated from composition rows instead of fixed panel/adviser/peer fields.
- If a required enabled component has no rubric, block schedule generation/confirmation.

PIT:

- PIT event configuration dialog shows composition rows.
- For Phase 1, rows are Panel and Peer only.
- If Peer is disabled, peer weight becomes 0 and peer evaluation should not be required.

### Grade Center

Grade Center should display composition from the grade snapshot:

- Panel score and weight if Panel component enabled
- Adviser score and weight if Adviser component enabled
- Peer score and weight if Peer component enabled

Do not show disabled components as missing.

### Reports

Reports should render enabled components only. For compatibility, they can still read fixed `panel_*`, `adviser_*`, and `peer_*` fields during Phase 1.

## Grade Calculation Plan

### Phase 1

Keep current final grade math:

```text
final = panel_score * panel_weight
      + adviser_score * adviser_weight
      + peer_score * peer_weight
```

For PIT:

```text
final = panel_score * panel_weight
      + peer_score * peer_weight
```

If Adviser is disabled for Capstone:

- `adviser_weight = 0`
- `adviser_score` is not required
- final grade ignores adviser

If Peer is disabled:

- `peer_weight = 0`
- peer evaluation is not required
- final grade ignores peer

### Snapshot Rule

When a `TeamGrade` row is created or synced:

- Copy component weights into `TeamGrade`.
- Copy assigned rubrics through existing schedule/config relationships.
- Existing grade rows should not automatically change if admin edits composition after grading starts, unless admin explicitly chooses "apply to existing unpublished grades".

This prevents historical grades from silently changing.

## What Happens If A Category Is Added Or Removed?

### In Phase 1

Allowed:

- Enable/disable built-in components.
- Edit weights.
- Edit display labels.
- Assign/change rubrics before grade is published.

Not allowed yet:

- Add completely new custom categories like "Documentation", "Prototype", or "Client Rating".

Reason:

- A new category needs a submission workflow.
- Without a workflow, the score has no trusted source.

### In Phase 2

We can support custom components if the client confirms the workflow.

Possible custom component types:

- `manual_admin`: admin enters score in Grade Center.
- `panel_extra`: panelists submit through a rubric like normal panel.
- `adviser_extra`: adviser submits through adviser grading.
- `external`: future evaluator role.

Phase 2 would require:

- `TeamGradeComponentScore` model.
- Dynamic grade center score editor.
- Dynamic report rendering.
- Dynamic completion checks.
- More flexible breakdown storage.

## Migration Plan

1. Create `GradeCompositionComponent` model.
2. Backfill component rows from existing configs:
   - Capstone stage configs: Panel/Adviser/Peer.
   - PIT event configs: Panel/Peer.
3. Update serializers to expose `components` while keeping old fields.
4. Update write serializers to accept `components`.
5. On save, mirror component rows back into old fixed fields.
6. Update frontend Grade Composition UI to render rows.
7. Update scheduler prefill logic to read components.
8. Update grade center display to prefer `components` when present.
9. Keep reports using old fixed fields until all grade snapshots are component-aware.

## Risks To Avoid

### Risk 1: Making Rubrics The Category Source Of Truth

Bad:

- "If there are three rubrics, then there are three categories."

Why dangerous:

- Draft rubrics could accidentally become categories.
- Duplicate rubrics could duplicate grade weights.
- Replacing a rubric could change composition.

Good:

- Composition owns categories.
- Rubrics are assigned to categories.

### Risk 2: Changing Published Grades

Bad:

- Admin changes composition and old final grades recalculate silently.

Good:

- Published grades are locked.
- Existing unpublished grades only update if explicitly re-synced.

### Risk 3: Allowing A Category With No Workflow

Bad:

- Add "Client Rating 10%" but no screen exists to submit Client Rating.

Good:

- Phase 1 only supports existing workflow-backed components.
- Phase 2 introduces custom component types with explicit score source.

### Risk 4: Breaking PIT By Adding Adviser

Bad:

- Let PIT enable Adviser without adviser submission flow.

Good:

- PIT only supports Panel and Peer in Phase 1.

## Recommended Implementation Scope

Best next implementation:

### Phase 1A: UI/API Dynamic Rows For Existing Categories

- Keep database fixed fields.
- Do not add custom category creation yet.
- Change API payloads to expose a `components` list derived from current fields.
- Change frontend to render composition rows from that list.
- Allow enable/disable by setting weight to 0 and `is_enabled = false`.

This gives the client a dynamic-looking composition editor with low risk.

### Phase 1B: Normalize Components In Database

- Add `GradeCompositionComponent`.
- Backfill rows.
- Keep old fields mirrored.
- Begin using components as canonical config source.

### Phase 2: True Custom Categories

- Only after client confirms who submits custom scores.
- Add dynamic score snapshot rows.
- Add dynamic report/grade center rendering.

## My Recommendation

Start with Phase 1A or Phase 1B, not Phase 2.

If the client only needs to edit Panel/Adviser/Peer for Capstone and Panel/Peer for PIT, Phase 1A may be enough and much safer.

If the client truly needs to add/remove categories in the database, do Phase 1B, but still restrict categories to known workflow types first.

Do not implement arbitrary custom grade categories until there is a clear answer for who submits each new category score.
