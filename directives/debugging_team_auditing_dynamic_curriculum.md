# Implementation Plan - Academic Periods, Seeder Auditing, and Dynamic Curriculum Stacks

This implementation plan details our proposed changes to address the three core concerns:
1. **Vertical UI Overflow**: Resolving the 16-pixel layout overflow on the Academic Period Management page.
2. **Missing Audit Trails**: Populating the system audit log database during student progression seeding with matching timestamps.
3. **Rigid Technology Stack Analytics**: Making the tech stack classification, trend charting, and coloring dynamic to support alternative languages and frameworks (e.g., Java, C#, Go).

---

## User Review Required

> [!IMPORTANT]
> - **Direct Database Update for Timestamps**: Because the seeder populates a historical timeline spanning 7 semesters (from 2023 to 2026), we must override the `auto_now_add=True` field of `SystemAuditLog.created_at` in Django. We will achieve this using `.update(created_at=...)`, which bypasses save lifecycle overrides and writes direct SQL updates.
> - **Evidence Logs with File Details (Approach 1)**: For file submission events (Repository Vault submissions and Capstone deliverables), we will store document metadata (such as `file_name`, `file_url`, and `file_size`) inside the audit log's `new_values` JSON field. This captures digital evidence directly within the log payload without requiring new model fields.
> - **Fully Dynamic Legend and Trend Charts**: The Curriculum Analytics frontend is already built dynamically to display whatever technologies are returned in the backend payload. By deriving unique tech stacks from the actual entries, alternative languages (e.g. `Spring Boot / Java`, `ASP.NET / C#`) will automatically render as bars and legend items on the client.
> - **HSL Color Hashing for Dynamic Stacks**: If a team uses a completely custom language/framework, the system will dynamically detect it and generate a curated, harmonious hex color using a deterministic HSL hash function. This ensures the UI remains visually premium and avoids color clashes or generic greys.

---

## Proposed Changes

### Frontend Components

#### [MODIFY] [academic_periods_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/academic_periods_screen.dart)
- Replace the root `Padding` widget in `_buildContent` with a `SingleChildScrollView` to make the content vertically scrollable when it exceeds the viewport height.
- Retain the exact padding structure by passing `padding: const EdgeInsets.fromLTRB(24, 20, 24, 36)`.

---

### Backend Components

#### [MODIFY] [seed_student_progression.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/management/commands/seed_student_progression.py)
- Import `SystemAuditLog` and write a helper function `log_historical_action` that:
  - Creates a `SystemAuditLog` entry.
  - Direct-updates `created_at` to write historical timestamps corresponding to each semester.
- Integrate logging for all critical seeder milestones:
  - **Academic Period Changes**: Log creating school years and activating semesters.
  - **Student Teams & Memberships**: Log student team creations, leader designations, and memberships.
  - **Repository Vault Submissions**: Log the upload and approval of PIT vault deliverables, using `audit_scope_metadata` to include required tracking scopes (`scope='pit'`) so that row-level visibilities match the PIT Lead role (`faculty.pit` / Grace Hopper). Store file details (such as `file_name`, `file_url`, and `file_size`) inside `new_values` as digital evidence.
  - **Capstone Deliverables**: Log submission and grading events, storing deliverable file metadata (such as `file_name`, `file_url`, and `file_size`) inside the `new_values` payload as digital evidence.
- Update the cleanup section of the seeder to delete old seeder-related `SystemAuditLog` records before seeding, ensuring a clean rerun.

#### [MODIFY] [services.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/curriculum_analytics/services.py)
- Rewrite `extract_tech(entry)` to perform a tiered keyword scanning:
  1. Check the document's text and topics for strong matches with our predefined stacks.
  2. If no predefined stack matches, scan for known programming language terms (e.g., `java`, `c#`, `golang`, `rust`, `cpp`, `ruby`, `rails`) and dynamically return a label like `Spring Boot / Java`, `ASP.NET / C#`, `Go / Fiber`, etc.
  3. If none of these are found, fall back to mapping using the Naive Bayes category and confidence score, defaulting to `Django / Python`.
- Update `stack_color(label)` to:
  - Return predefined brand colors for primary stacks (including Java, C#, Go).
  - Determine dynamic colors using a hashing function that computes a unique hue and returns a tailored HSL hex color.
- Modify `trend_series` to compute all unique technologies from the *actual database records* in the dataset (`{entry['tech_stack'] for entry in entries}`) rather than iterating strictly over a hardcoded static array of 8 stacks.
- Dynamically compile the `taxonomy` list based on present technologies rather than a hardcoded array.

---

## Verification Plan

### Automated Verification
- Run the django command to test backend execution:
  ```powershell
  python manage.py seed_student_progression
  ```
- Run the django test suite to verify no regressions:
  ```powershell
  python manage.py test --keepdb
  ```

### Manual Verification
- **Audit Trail UI**: Log in as `admin` or `faculty.pit` (Grace Hopper) and verify that the **Audit Trail** register is populated with historical events.
- **Academic Periods UI**: Resize the browser window and verify that the **Academic Period Management** screen scrolls smoothly without displaying layout overflow stripes.
- **Curriculum Analytics UI**: Verify that any custom technology stacks display accurately on the distribution bars and the 3-Year Trend chart with appropriate matching colors.
