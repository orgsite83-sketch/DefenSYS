# PIT And Capstone Deliverables Separation & Scope Rules

## Objective
This directive defines the rules and protocols for absolute separation between Capstone stage-based deliverables and PIT event-based deliverables. It also enforces scoping rules to ensure PIT Leads of specific year levels can only manage their respective year's PIT deliverables, while preventing them from viewing or modifying Capstone deliverables (which are restricted to Administrators, the team's assigned Adviser, and the team members themselves).

---

## 1. Core Structural Separation

Deliverables in DefenSYS are categorized into two completely distinct flows:

### 1.1. Capstone Deliverables Flow (Stage-Based)
* **Authoritative Abstractions**: Managed using `DefenseStage` and `StageDeliverable` configurations.
* **Stage Identifiers**: Stage labels are retrieved dynamically from active `DefenseStage` records (e.g., "Proposal Defense", "Oral Defense").
* **Scoping Restrictions**:
  * Only accessible by:
    1. System Administrators / Superusers.
    2. Assigned Capstone Advisers (for their specific advised teams).
    3. Team Members (students).
  * **Critical Guard**: PIT Leads must NOT have access to Capstone deliverables.

### 1.2. PIT Deliverables Flow (Event-Based)
* **Authoritative Abstractions**: Managed using `PitEventGradingConfig` and `PitEventDeliverable` configurations.
* **Stage Identifiers**: Stage labels are retrieved dynamically from the active semester's configured `PitEventGradingConfig` event names (e.g., "PIT Expo").
* **Scoping Restrictions**:
  * Only accessible by:
    1. System Administrators / Superusers.
    2. Respective PIT Leads of the matching year level (e.g., a "3rd Year PIT Lead" can only manage "3rd Year PIT" deliverables).
    3. Team Members (students).
  * **Critical Guard**: Advisers cannot manage PIT deliverables unless they are also the assigned PIT Lead for that year level or explicitly permitted. PIT Leads of one year level must NOT see or modify deliverables of PIT teams in another year level.

---

## 2. Dangerous Logic & Vulnerability Safeguards

To prevent cross-pollution and security leaks, the system must enforce the following safeguards:

### 2.1. Dynamic Serializer Choices Validation
* **The Risk**: Hardcoding serializer validation choices to Capstone stages (`STAGE_OPTIONS`) prevents PIT event-based uploads, causing DRF choice validation failures.
* **The Rule**: Change `stage_label` from a static `ChoiceField` to a `CharField` in the deliverables serializer. Perform dynamic validation in the serializer's `validate()` method:
  * If the target team is a Capstone team, verify that `stage_label` matches an active `DefenseStage.label`.
  * If the target team is a PIT team, verify that `stage_label` matches a configured `PitEventGradingConfig.event_name` for the team's semester.

### 2.2. Query Scoping and Year-Level Leakage Prevention
* **The Risk**: Filtering PIT Lead scope using `level__icontains=pit_year` matches both `"3rd Year PIT"` and `"3rd Year Capstone"` teams, leaking Capstone teams to PIT Leads.
* **The Rule**: Always pair the year-level filter with a check for `"PIT"` in the level field:
  * For example, query filters for PIT Lead team scoping must be:
    `Q(level__icontains=pit_lead_year) & Q(level__icontains='PIT')`
  * If `pit_lead_year` is empty, fall back to `Q(level__icontains='PIT')`.
  * This guarantees PIT Leads can never retrieve Capstone teams.

### 2.3. Permission Enforcement
* **The Rule**: Extend the `CanManageDeliverables` permission class to allow PIT Leads to manage deliverables, but rely on the scoped `get_allowed_team(request, team_id)` helper (which uses the corrected `team_queryset_for_user`) to restrict edit access to their authorized teams.

---

## 3. Frontend Separation

The deliverables interface must adapt visually based on the active user track/scope:

### 3.1. Navigation Entry
* **Project Adviser Workspace**: Sidebar menu item remains "Capstone Deliverables".
* **PIT Lead Workspace**: Sidebar menu item is "PIT Deliverables". Both direct to the deliverables route but with a context scope parameter (`scope = 'pit'` or `'capstone'`).

### 3.2. Adaptable User Interface (Capstone vs. PIT)
* When operating in `pit` scope:
  * The main page title must display "PIT Deliverables".
  * The teams count badge must label teams as "PIT Teams".
  * The stage selector dropdown must label the filter as "PIT Event".
  * Empty states must show "No PIT teams found".
* When operating in `capstone` scope:
  * Retain all Capstone-centric titles, labels, and helper texts.
