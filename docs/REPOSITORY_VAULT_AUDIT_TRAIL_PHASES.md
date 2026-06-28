# Repository Vault and Audit Trail Phases

## Goal

Split the current repository audit wording into two clear areas:

- **Repository Vault**: the repository upload, archive, vault record, and per-file evidence workflow.
- **Audit Trail**: the review area for official evidence and audit events, with the page title **Audit Trail & Evidence Review**.

Repository Vault should cover both Capstone and PIT:

- Admin users see the global view across Capstone, PIT, and all records.
- PIT leaders see only PIT records for the year level they handle.

Audit Trail should remain separate from the Repository Vault upload workflow. Admins can review all audit records, while PIT leaders can review Audit Trail records for their assigned PIT year level.

## Recommendation

Do not start by creating a brand-new Django app named `audit`.

The project already has repository audit code under:

- `backend/modules/repository/audit/`
- `backend/modules/authentication_access_control/audit.py`

The safest approach is to improve the existing repository audit module as **Repository Vault** first, then improve the separate **Audit Trail** review experience. Only introduce a broader shared audit module when multiple areas depend on the same audit model and review workflow.

In short:

- Use `repository/audit` for Repository Vault records, upload history, archive evidence, and PIT/Capstone repository scope.
- Use the existing system audit logging for Audit Trail records covering high-impact academic and access actions.
- Keep Repository Vault and Audit Trail as separate navigation items.
- Create a broader `audit` module later only if Audit Trail becomes a shared cross-module product, not just a page backed by existing logs.

## Phase 1: UI Naming and Navigation

Purpose: make the two areas clear without changing backend behavior.

Replace the old **Repository Audit** label with **Repository Vault**. Keep the audit review area separate as **Audit Trail**.

Suggested changes:

- Admin repository sidebar label: **Repository Vault**
- Faculty/PIT lead repository sidebar label: **Repository Vault**
- Admin audit sidebar label: **Audit Trail**

- PIT lead audit sidebar label: **Audit Trail**
- Repository page title: **Repository Vault**
- Repository page internal section title: **Repository Vault Records**
- Audit review page title: **Audit Trail & Evidence Review**
- Top filter chip: **All files** becomes **All records**

Keep the existing top chips:

- Capstone
- PIT
- All records

## Phase 2: Preserve Repository Vault Scope Rules

Purpose: make PIT and Capstone repository access work correctly before adding more audit review features.

Admin view:

- Can see Capstone records.
- Can see PIT records for all year levels.
- Can use **All records** as a global view.

PIT leader view:

- Defaults to PIT.
- Shows only the PIT year level assigned to that PIT leader.
- Does not show unrelated Capstone records.
- Does not show PIT records from other year levels.

Implementation note:

The current repository audit screen already uses scope values like `pit_lead` and `pit_year_level`. Reuse those rules for Repository Vault instead of creating a separate permission system.

Audit Trail should reuse the same PIT year-level boundary for PIT leaders:

- Admin users can review Audit Trail records across Capstone, PIT, and all year levels.
- PIT leaders can review Audit Trail records only for their assigned PIT year level.
- PIT leaders should not see unrelated Capstone audit records.
- PIT leaders should not see PIT audit records from other year levels.

## Phase 3: Repository Vault Records

Purpose: keep the repository workflow useful while organizing it as a vault and evidence area.

The repository screen should remain responsible for:

- PIT PDF upload.
- Capstone PDF upload.
- Archive readiness.
- Vault record status.
- Upload queues.
- CSV export.
- Per-file evidence history.

This phase should not remove or replace existing upload behavior. It should organize the screen so it feels like a vault and evidence area instead of a developer audit log.

Recommended screen sections:

- Repository Vault Summary
- Repository Vault Records
- Upload Queue
- File Evidence Details
- Per-file Evidence History

## Phase 4: Audit Trail & Evidence Review

Purpose: create the separate audit review experience shown in the concept screenshot.

The audit review page should focus on evidence review, not file upload. It should support both the admin global review view and the PIT leader scoped review view.

Recommended sections:

- Audit readiness summary.
- Evidence status cards.
- Review status filters.
- Category cards.
- Audit trail table.
- Evidence details panel.

Recommended audit categories:

- Academic Period Changes
- Grade & Result Decisions
- Schedule Changes
- Team Adviser Changes
- Repository Vault Evidence
- Guest Access Activity

This phase can start as mostly UI and filtering work if the existing providers already expose the needed records. It should not absorb Repository Vault upload queues or vault record management.

Scope behavior:

- Admins can use the page as a global evidence review area.
- PIT leaders default to their assigned PIT year level.
- PIT leaders only see categories and records that apply to their scoped PIT records.

## Phase 5: Backend Audit Consolidation

Purpose: decide whether a true shared audit app is needed.

Only create a broader audit module after the Repository Vault UI, Audit Trail UI, and access scopes are approved.

Create a shared audit module if these become true:

- Multiple modules need the same Audit Trail record shape.
- Admins need one review queue across grading, scheduling, repository, access, and academic periods.
- Review status needs to be stored consistently across all audit categories.
- Evidence cards need one API instead of many category-specific endpoints.

Possible future module name:

- `backend/modules/audit/`

Possible responsibilities:

- Shared Audit Trail event model.
- Evidence review status.
- Category and control IDs.
- Actor, target, before/after metadata.
- Review notes.
- Admin global filtering.
- Scoped filtering for PIT leaders and advisers if Audit Trail access expands beyond admins and PIT leaders.

Do not move Repository Vault upload logic into this future module. Uploads and vault records should stay in repository. The shared audit module should store audit events, evidence review status, and review notes only.

## Phase 6: Tests and Safety Checks

Purpose: protect Repository Vault permission boundaries and avoid leaking PIT records across year levels.

Recommended tests:

- Admin can see Capstone, PIT, and All records.
- PIT leader only sees assigned year-level PIT records.
- PIT leader cannot see another year level's PIT records.
- Capstone records do not appear in PIT leader scoped views.
- The **All records** chip respects the user's scope.
- Existing repository upload tests still pass.
- Audit Trail remains separate from Repository Vault upload and queue behavior.
- Admin can review global Audit Trail records.
- PIT leader can review only assigned year-level Audit Trail records.
- PIT leader cannot review Audit Trail records from other PIT year levels or unrelated Capstone records.

## Suggested Order

1. Rename labels and titles so Repository Vault and Audit Trail are separate.
2. Change **All files** to **All records**.
3. Verify admin/PIT leader scoped repository views.
4. Improve the audit review page title and category layout.
5. Add PIT leader scoped Audit Trail review.
6. Add evidence review filters/cards.
7. Decide later whether `backend/modules/audit/` is necessary.

## Final Recommendation

Yes, Audit Trail can eventually become a dedicated audit module, but not as the first step.

For now, keep Repository Vault behavior in `backend/modules/repository/audit/`. Keep Audit Trail as a separate review area backed by existing audit logs where possible, with admin global review and PIT leader year-level review. After that, if Audit Trail needs to unify repository, grading, schedule, academic period, and access records into one review queue, then create a shared `backend/modules/audit/` module.
