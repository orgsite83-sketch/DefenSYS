# Documenter Role & Minutes of Defense

> **Status:** Design finalized — awaiting implementation approval  
> **Scope:** Capstone defenses only  
> **Platform:** Faculty Web

---

## 1. Overview

The **Repository Assistant** role is being **removed** (clean break — `is_repo_assistant`, `repo_assistant_year`, and all related code are deleted). In its place, a new **Documenter** role is introduced as a **two-layer concept**:

1. **User-level capability flag** (`is_documenter`) — toggled on the **Access Control & Role Assignment** screen (replacing the Repository Assistant toggle). This marks which faculty are eligible to serve as documenters.
2. **Per-defense-schedule assignment** — a `documenter` FK on `DefenseSchedule`, set at scheduling time. Only faculty with `is_documenter = True` can be assigned.

### What the Documenter does

1. Views their assigned defense schedules on a dedicated **Documenter Dashboard**
2. Opens a minutes form for each defense
3. Records **per-panelist comments** (one text block per panelist)
4. Saves drafts and finalizes when done
5. E-signs the completed minutes (first in a three-step signing flow)

---

## 2. Data Model Changes

### 2.1 Remove Repository Assistant → Replace with Documenter flag

> **Codebase audit complete.** Every reference to `is_repo_assistant`, `repo_assistant_year`, `ROLE_REPO_ASSISTANT`, `repository_assistant`, and `repoAssistant` has been catalogued below.

---

#### 2.1.1 Backend files to DELETE entirely

| File | Why |
|------|-----|
| [pit_repository_assistant.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/pit_repository_assistant.py) | Entire module: `current_repo_assistant_for_year()`, `has_repo_assistant_for_year()`, `_revoke_repo_assistant()`, `repository_assistant_assignment_payload()`, `assign_repository_assistant()`, `require_pit_lead()`, `faculty_assignment_candidates()` | Done

#### 2.1.2 Backend files to MODIFY

**[models.py (User)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/models.py)**
- **L30:** Remove `is_repo_assistant = models.BooleanField(default=False)`
- **L31:** Remove `repo_assistant_year = models.CharField(max_length=50, blank=True, default='')`
- **Add:** `is_documenter = models.BooleanField(default=False)`

**[serializers.py (auth)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/serializers.py)**
- **L32:** Remove `'is_repo_assistant', 'repo_assistant_year'` from `fields`
- **L46:** Remove `'repoAssistant': obj.is_repo_assistant,`
- **L47:** Remove `'repoAssistantYear': getattr(obj, 'repo_assistant_year', '') or '',`
- **Add:** `'documenter': obj.is_documenter,`

**[tests.py (auth)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/tests.py)**
- **L216:** Remove `is_repo_assistant=True,`
- **L418:** Remove/rewrite `test_repository_assistant_cannot_review_audit_trail`

**[models.py (FacultyRoleAssignment)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/models.py)**
- **L55:** Change `ROLE_REPO_ASSISTANT = 'repo_assistant'` → `ROLE_DOCUMENTER = 'documenter'`
- **L61:** Change `(ROLE_REPO_ASSISTANT, 'Repository Assistant')` → `(ROLE_DOCUMENTER, 'Documenter')`

**[role_assignments.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/role_assignments.py)**
- **L10:** Change `FacultyRoleAssignment.ROLE_REPO_ASSISTANT: 'Repository Assistant'` → `FacultyRoleAssignment.ROLE_DOCUMENTER: 'Documenter'`
- **L18:** Change `('repo_assistant', 'Repository Assistant', 'repo_assistant')` → `('documenter', 'Documenter', 'documenter')`
- **L31:** Change `FacultyRoleAssignment.ROLE_REPO_ASSISTANT: user.is_repo_assistant` → `FacultyRoleAssignment.ROLE_DOCUMENTER: user.is_documenter`
- **L44–45:** Change `ROLE_REPO_ASSISTANT` branch → `ROLE_DOCUMENTER` returning `None` (no year needed)
- **L135–138:** Change `if user.is_repo_assistant:` block → `if user.is_documenter:` with label `'Documenter'`

**[serializers.py (user_management)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/serializers.py)**
- **L120:** Change `'is_repo_assistant'` → `'is_documenter'` in fields
- **L145:** Change `'repoAssistant': obj.is_repo_assistant` → `'documenter': obj.is_documenter`
- **L201, L206:** Change `attrs['is_repo_assistant'] = False` → `attrs['is_documenter'] = False`

**[views.py (user_management)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py)**
- **L121:** Remove/change `users.filter(role__in=['faculty', 'admin'], is_repo_assistant=True)` — if this filter is for repo assistants only, remove it or change to `is_documenter=True`

**[tests.py (user_management)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/tests.py)**
- **L139:** Change `'is_repo_assistant': True` → `'is_documenter': True`
- **L149:** Change `response.data['user']['facultyRoles']['repoAssistant']` → `response.data['user']['facultyRoles']['documenter']`

**[views.py (dashboards)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py)**
- **L48:** Remove `from .pit_repository_assistant import current_repo_assistant_for_year`
- **L111:** Remove `'repo_assistant': user.is_repo_assistant,` — add `'documenter': user.is_documenter,`
- **L112:** Remove `'repo_assistant_year': ...`
- **L130–131:** Remove `if user.is_repo_assistant: labels.append('Repository Assistant')` — add `if user.is_documenter: labels.append('Documenter')`
- **L800:** Remove `current_repo_assistant_for_year(user.pit_lead_year)` call
- **L815–818:** Remove `'is_repo_assistant'` and `'repo_assistant_year'` and `'repository_assistant'` from PIT lead payload — add `'is_documenter': user.is_documenter`
- **L833–841:** Remove entire `PitLeadRepositoryAssistantView` GET/POST methods (or the whole view class)

**[urls.py (dashboards)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/urls.py)**
- **L9:** Remove `PitLeadRepositoryAssistantView` import
- **L26–30:** Remove the `pit-lead/repository-assistant/` URL pattern

**[tests.py (dashboards)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/tests.py)**
- **L45:** Remove `is_repo_assistant=True,`
- **L55:** Remove `self.assertTrue(response.data['roles']['repo_assistant'])` — add `is_documenter` equivalent

**[services.py (repository audit)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/services.py)**
- **L88–89:** Remove `is_repo_assistant=True, repo_assistant_year=year_level` filter
- **L652–653:** Remove `is_repo_assistant` check in `repository_scope()` — decide: documenters should NOT have audit access (their role is different), so remove this branch entirely
- **L656:** Remove `'Repository assistant PIT uploads'` label
- **L664:** Update error message: remove "repository assistants"

**[tests.py (repository audit)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/tests.py)**
- **L410–434:** Remove `test_pit_lead_assigns_repository_assistant_and_revokes_previous` test and all `repo_assistant_faculty` references

**[check_uploader.py (archive test)](file:///c:/Users/Admin/Desktop/DefenSYS/backend/tests/archive/check_uploader.py)**
- **L37:** Remove `print(f"Is Repo Assistant: {user.is_repo_assistant}")`
- **L45:** Remove `not user.is_repo_assistant` condition

---Done

#### 2.1.3 Frontend files to DELETE entirely

| File | Why |
|------|-----|
| [pit_repository_assistant_provider.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/services/pit_repository_assistant_provider.dart) | Entire provider: fetches/assigns repo assistant |
| [pit_repository_assistant_card.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/pit_repository_assistant_card.dart) | Entire widget: the PIT lead dashboard card for assigning repo assistant |
Done

#### 2.1.4 Frontend files to MODIFY

**[session_providers.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/services/session_providers.dart)**
- **L15:** Remove `import 'pit_repository_assistant_provider.dart';`
- Remove any `ChangeNotifierProvider` registration for the deleted provider

**[faculty_dashboard.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/faculty_dashboard.dart)**
- **L32:** Remove `repoAssistant` from `FacultyWorkspace` enum (or rename to `documenter`)
- **L179:** Remove `workspaces.add(FacultyWorkspace.repoAssistant);` — add documenter workspace logic
- **L207–208:** Remove `case FacultyWorkspace.repoAssistant: return 'Repository Assistant';`
- **L763:** Remove `case FacultyWorkspace.repoAssistant:` content-building case
- **L1109–1126:** Remove `case FacultyWorkspace.repoAssistant:` and its `repo_assistant_year` references

**[pit_lead_dashboard_content.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/pit_lead_dashboard_content.dart)**
- **L4:** Remove `import 'pit_repository_assistant_card.dart';`
- Remove the `PitRepositoryAssistantCard` widget from the PIT lead dashboard layout

**[user_management_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart)**
- **L85:** Rename `bool _acRepoAssistant = false;` → `bool _acDocumenter = false;`
- **L3307–3308:** Change `_acRepoAssistant = (user['is_repo_assistant'] == true) || ...` → `_acDocumenter = user['is_documenter'] == true;`
- **L3362:** Change `'is_repo_assistant': isFaculty && _acRepoAssistant` → `'is_documenter': isFaculty && _acDocumenter`
- **L3363:** Decouple `'is_uploader'` from repo assistant — `is_uploader` should be managed independently
- **L3664:** Change `_acRepoAssistant = false;` → `_acDocumenter = false;`
- **L3749:** Change title `'Repository Assistant'` → `'Documenter'`
- **L3753, L3757:** Change `_acRepoAssistant` → `_acDocumenter`
- **L4224:** Change `'is_repo_assistant': false` → `'is_documenter': false`
- **L4242–4245:** Change all `is_repo_assistant` references → `is_documenter`
- **L4592, L4603–4604:** Change payload keys from `is_repo_assistant` / `is_uploader` tied to `_acRepoAssistant` → `is_documenter` tied to `_acDocumenter`
- **L4660–4661:** Change `isRepoAssistant` variable → `isDocumenter`
- **L4782, L4829, L4833, L4837:** Change all `isRepoAssistant` / `'Repository Assistant'` → `isDocumenter` / `'Documenter'`
- **L4883–4884:** Change payload `'is_repo_assistant': isRepoAssistant` → `'is_documenter': isDocumenter`

**[repository_audit_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/shared/repository_audit_screen.dart)**
- **L198:** Remove "Your assigned Repository Assistant handles uploads" text
- **L284:** Remove "Uploads are handled by your Repository Assistant" text
- **L428:** Remove "Assign a Repository Assistant on your dashboard to delegate uploads" text
- Replace with appropriate text or remove the references entirely

**[migrate_auth_client.py (frontend script)](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/scripts/migrate_auth_client.py)**
- **L17:** Remove `'lib/services/pit_repository_assistant_provider.dart'` from file list

---Done

#### 2.1.5 Documentation to UPDATE

| File | Changes |
|------|---------|
| [DEFENSYS_REAL_SYSTEM_FLOW.md](file:///c:/Users/Admin/Desktop/DefenSYS/docs/DEFENSYS_REAL_SYSTEM_FLOW.md) | **L113:** Remove `is_repo_assistant` row from faculty flags table. **L650:** Remove `pit_repository_assistant_provider` row from providers table. Add `is_documenter` row. |
| [SYSTEM_OVERVIEW.md](file:///c:/Users/Admin/Desktop/DefenSYS/docs/SYSTEM_OVERVIEW.md) | **L82:** Remove `is_repo_assistant` from faculty flags list, add `is_documenter` |
| [REPOSITORY_VAULT_AUDIT_TRAIL_PHASES.md](file:///c:/Users/Admin/Desktop/DefenSYS/docs/REPOSITORY_VAULT_AUDIT_TRAIL_PHASES.md) | **L14, L46, L77, L92, L175, L188, L201:** Remove all "Repository Assistant" references |
| [WORK_ROLE_ASSIGNMENT_MODEL_PLAN.md](file:///c:/Users/Admin/Desktop/DefenSYS/docs/WORK_ROLE_ASSIGNMENT_MODEL_PLAN.md) | **L42, L107, L426, L455:** Remove/replace "Repository Assistant" references |
| [PIT_COHORT_OFFICIAL_CLASS_LIST_IMPORT_PLAN.md](file:///c:/Users/Admin/Desktop/DefenSYS/docs/PIT_COHORT_OFFICIAL_CLASS_LIST_IMPORT_PLAN.md) | **L300:** Remove "repository assistant" from role list |
| [FEATURE_AUDIT.md (archive)](file:///c:/Users/Admin/Desktop/DefenSYS/docs/archive/prototype/FEATURE_AUDIT.md) | **L30:** Remove Repo Assistant row |
Done

#### 2.1.6 Migration note

The migration for `0001_initial.py` (auth) already has `is_repo_assistant` baked in. A new migration will:
1. Add `is_documenter` field
2. Remove `is_repo_assistant` and `repo_assistant_year` fields

The `0003_user_repo_assistant_year.py` migration added the year field — both fields get removed in the new migration. **No data migration needed** — existing repo assistant assignments are discarded.

---

**Add (new field):**
```python
# authentication_access_control/models.py — User
is_documenter = models.BooleanField(default=False)
```

**Update Access Control & Role Assignment screen** (`user_management_screen.dart`):
- Replace the "Repository Assistant" toggle with a **"Documenter"** toggle
- Icon: 📋 or similar document icon
- Description: "Records minutes of defense for capstone teams."
- No dependent fields (unlike PIT Lead which has `pit_lead_year`)

**Update `FacultyRoleAssignment`:**
- Replace `ROLE_REPO_ASSISTANT` with `ROLE_DOCUMENTER = 'documenter'`
- Update `snapshot_role_flags()` and `record_role_changes()` in `role_assignments.py`
- Update display role priority: admin → PIT lead → adviser → panelist → **documenter**

**Keep:** `User.is_uploader` (still used independently for document uploads)
Done

### 2.2 Add `documenter` FK on `DefenseSchedule`

```python
# defense/scheduler/models.py — DefenseSchedule
documenter = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    related_name='documenter_defense_schedules',
    null=True,
    blank=True,
    on_delete=models.SET_NULL,
    help_text='Faculty assigned as documenter for this capstone defense.',
)
```

**Validation rules:**
- Only allowed when `scope == 'capstone'` (PIT schedules cannot have a documenter)
- Must be a faculty/admin user (`role in ['faculty', 'admin']`)
- Must have `is_documenter = True` (only eligible faculty can be assigned)
- Must NOT be one of the panelists assigned to the same schedule
- Must NOT be the team's adviser
- Optional (nullable) — a schedule can exist without a documenter initially
Done

### 2.3 Add `is_chair` on `SchedulePanelist`

```python
# defense/scheduler/models.py — SchedulePanelist
is_chair = models.BooleanField(default=False)
```

**Validation:** At most one panelist per schedule can be marked as chair.
Done

### 2.4 Add e-signature field on `User`

```python
# authentication_access_control/models.py — User
e_signature = models.ImageField(
    upload_to='e_signatures/',
    null=True,
    blank=True,
    help_text='Uploaded e-signature image (PNG/JPG) for document signing.',
)
```

Faculty upload their e-signature image once via their profile. This image is placed on the minutes PDF when they sign. 
Done

### 2.5 New model: `DefenseMinutes`

```python
# defense/minutes/models.py (NEW submodule)

class DefenseMinutes(models.Model):
    STATUS_DRAFT = 'draft'
    STATUS_SUBMITTED = 'submitted'           # Documenter signed
    STATUS_ADVISER_SIGNED = 'adviser_signed'  # Adviser signed
    STATUS_COMPLETED = 'completed'            # Chairman signed — fully done

    STATUS_CHOICES = (
        (STATUS_DRAFT, 'Draft'),
        (STATUS_SUBMITTED, 'Submitted'),
        (STATUS_ADVISER_SIGNED, 'Adviser Signed'),
        (STATUS_COMPLETED, 'Completed'),
    )

    schedule = models.OneToOneField(
        'defense.DefenseSchedule',
        related_name='minutes',
        on_delete=models.CASCADE,
    )

    # Auto-filled from schedule (snapshotted for record integrity)
    team_name = models.CharField(max_length=120)
    project_title = models.CharField(max_length=255)
    adviser_name = models.CharField(max_length=160)
    defense_stage_label = models.CharField(max_length=120)
    defense_date = models.DateField()
    defense_time = models.TimeField()
    room = models.CharField(max_length=120)
    documenter_name = models.CharField(max_length=160)

    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DRAFT)

    # E-signatures (timestamped)
    documenter_signed_at = models.DateTimeField(null=True, blank=True)
    documenter_signed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_signed_as_documenter',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )
    adviser_signed_at = models.DateTimeField(null=True, blank=True)
    adviser_signed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_signed_as_adviser',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )
    chairman_signed_at = models.DateTimeField(null=True, blank=True)
    chairman_signed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_signed_as_chairman',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )

    # Generated PDF (after all signatures)
    pdf_file = models.FileField(upload_to='defense_minutes/', null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```
Done

### 2.6 New model: `MinutesPanelistComment`

```python
class MinutesPanelistComment(models.Model):
    minutes = models.ForeignKey(
        DefenseMinutes,
        related_name='panelist_comments',
        on_delete=models.CASCADE,
    )
    panelist = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_comments_about',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )
    panelist_name_snapshot = models.CharField(max_length=160)
    panelist_role_snapshot = models.CharField(max_length=40, blank=True)  # 'Chair', 'Panel Member 1', etc.
    comments = models.TextField(blank=True)
    display_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```
Done

---

## 3. API Endpoints

### 3.1 Documenter Dashboard

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/defense/minutes/my-assignments/` | JWT (faculty) | List all defense schedules where the user is assigned as documenter |

Returns schedule details + minutes status (draft/submitted/completed).
Done

### 3.2 Minutes CRUD

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/defense/minutes/<schedule_id>/` | JWT (documenter/adviser/admin) | Get minutes for a schedule (auto-creates draft if none exists) |
| PATCH | `/api/defense/minutes/<schedule_id>/` | JWT (documenter only) | Update panelist comments (save draft) |
| POST | `/api/defense/minutes/<schedule_id>/submit/` | JWT (documenter only) | Documenter signs and submits |
| POST | `/api/defense/minutes/<schedule_id>/sign-adviser/` | JWT (adviser of the team) | Adviser reviews and signs |
| POST | `/api/defense/minutes/<schedule_id>/sign-chairman/` | JWT (admin) | Chairman reviews and signs → generates PDF |
| GET | `/api/defense/minutes/<schedule_id>/pdf/` | JWT (authorized users) | Download the generated PDF |
Done

### 3.3 E-Signature Upload

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| POST | `/api/users/e-signature/` | JWT (faculty/admin) | Upload e-signature image |
| DELETE | `/api/users/e-signature/` | JWT (faculty/admin) | Remove e-signature |
Done

### 3.4 Modified existing endpoints

- `POST /api/defense/schedules/` — add optional `documenter` field (faculty user ID)
- `PATCH /api/defense/schedules/<id>/` — allow updating `documenter`
- Serializer includes `documenter` in response
- `SchedulePanelist` serializer includes `is_chair` field

---
Done

## 4. Signing Flow

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│   DRAFT     │────▶│  SUBMITTED   │────▶│ADVISER_SIGNED│────▶│  COMPLETED    │
│             │     │              │     │              │     │               │
│ Documenter  │     │ Documenter   │     │ Adviser      │     │ Chairman      │
│ fills in    │     │ e-signs      │     │ e-signs      │     │ e-signs       │
│ comments    │     │              │     │              │     │ PDF generated │
└─────────────┘     └──────────────┘     └──────────────┘     └───────────────┘
                         │                     │                     │
                    Notification          Notification          Notification
                    to Adviser            to Chairman           to Documenter
                                                               ("Minutes finalized")
```

### Signing rules:
- **Documenter** can only sign after all panelist comment fields are non-empty
- **Adviser** can only sign after the documenter has signed (status = `submitted`)
- **Chairman** can only sign after the adviser has signed (status = `adviser_signed`)
- **Chairman** is automatically determined as the `created_by` admin on the `DefenseSchedule`
- Each signer must have an **uploaded e-signature** — the system blocks signing without one
- Once signed, the minutes cannot be edited (locked at each stage)

---
Done

## 5. Notifications

| Trigger | Recipient | Title | Message |
|---------|-----------|-------|---------|
| Documenter assigned to schedule | Documenter | "Documenter Assignment" | "You have been assigned as documenter for {team}'s {stage} defense on {date} at {time}" |
| Documenter signs (submits) | Adviser | "Minutes Ready for Review" | "The minutes for {team}'s {stage} defense are ready for your review and signature" |
| Adviser signs | Chairman (admin) | "Minutes Awaiting Final Signature" | "The minutes for {team}'s {stage} defense have been reviewed by the adviser and await your signature" |
| Chairman signs (completed) | Documenter | "Minutes Finalized" | "The minutes for {team}'s {stage} defense have been finalized with all signatures" |

---Done

## 6. PDF Generation

The generated PDF matches the template format:

### Header (auto-filled):
- Team Name, Capstone Project title
- Adviser name
- Defense Stage (e.g., "Proposal Defense", "Final Defense")
- Date, Time, Room
- Panel Members (with Chair identified)
- Documenter name

### Body:
- **Per-panelist comment blocks**: "Chair: {name}" followed by comments, then "Panel Member 1: {name}", etc.

### Footer:
- Three signature blocks arranged horizontally:
  - Documenter: e-signature image + printed name + "Documenter" label + date signed
  - Adviser: e-signature image + printed name + "Adviser" label + date signed
  - Chairman: e-signature image + printed name + "Chairman" label + date signed

Done

---

## 7. Frontend Changes

### 7.1 New screens/components (Faculty Web)
- **`documenter_dashboard_content.dart`** — Documenter's list of assigned defenses with status badges
- **`minutes_form_screen.dart`** — The minutes editing form with auto-filled header + per-panelist comment fields
- **`e_signature_upload_dialog.dart`** — Upload/manage e-signature image (reusable component)

### 7.2 New providers
- **`documenter_provider.dart`** — Fetches documenter assignments and minutes data
- **`e_signature_provider.dart`** — Manages e-signature upload/delete

### 7.3 Modified screens
- **`faculty_dashboard.dart`** — Add "Documenter" tab/section when user has documenter assignments
- **`defense_scheduler_screen.dart`** — Add documenter field in schedule creation/edit form
- **`defense_board_screen.dart`** — Show minutes status for each capstone schedule
- **User profile / settings** — Add e-signature upload section

### 7.4 Remove
- **`pit_repository_assistant_card.dart`** — Remove from PIT lead dashboard
- **`pit_repository_assistant_provider.dart`** — Delete entirely

---Done

## 8. Migration Plan

### Backend migrations (in order):
1. Add `is_documenter` on `User` (replaces `is_repo_assistant`)
2. Remove `is_repo_assistant` and `repo_assistant_year` from `User`
3. Add `DefenseMinutes` and `MinutesPanelistComment` models
4. Add `documenter` FK on `DefenseSchedule`
5. Add `is_chair` on `SchedulePanelist`
6. Add `e_signature` on `User`
7. Update `FacultyRoleAssignment`: replace `ROLE_REPO_ASSISTANT` with `ROLE_DOCUMENTER`
8. Update Access Control UI: replace Repository Assistant toggle with Documenter toggle

### Data migration:
- No data to migrate — repo assistant assignments are discarded
- Existing schedules will have `documenter = NULL` (no documenter assigned yet)

---

## 9. Edge Cases

| Scenario | Behavior |
|----------|----------|
| Schedule deleted before minutes finalized | `DefenseMinutes` cascade-deletes with schedule |
| Documenter reassigned mid-draft | Old documenter loses access; new documenter sees existing draft. Signatures reset to draft status. |
| Adviser changed on team after minutes started | Minutes retain the snapshotted adviser name. The current adviser signs (not the snapshot). |
| Faculty has no e-signature uploaded | Signing button disabled with tooltip "Upload your e-signature first" |
| Chairman (admin) who created the schedule is deactivated | Any active admin can sign as chairman |
| Defense schedule status is 'cancelled' | Minutes form is locked/hidden |
| Multiple schedules for same team (re-defense) | Each schedule has its own independent minutes |
