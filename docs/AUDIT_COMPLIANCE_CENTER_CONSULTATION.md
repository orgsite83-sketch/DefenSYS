# Audit & Compliance Center Consultation Notes

## Purpose

This document explains the proposed audit improvement for DefenSYS based on Phase 2 item 13 of the developer improvement audit: **Add explicit audit logs for high-impact actions**.

The goal is to make important academic and access-related actions traceable in a way that is understandable for administrators, advisers, and future auditors.

This proposal is for adviser consultation only. It does not require implementing a full system-wide audit module immediately.

## Main Idea

DefenSYS should record evidence whenever a high-impact action happens.

Examples of high-impact actions include:

- Changing the active academic period.
- Publishing or finalizing grades.
- Marking a stage or event as officially complete.
- Cancelling, deleting, or marking schedules as done.
- Changing a team adviser.
- Uploading or replacing repository archive files.
- Creating, exchanging, or using guest panelist access codes.

Each audit record should answer:

- Who performed the action?
- What action was performed?
- Which record was affected?
- What changed before and after?
- When did it happen?
- Was a reason provided?
- Is the evidence reviewed or still pending?

## Important Scope Decision

For now, the system should **not immediately combine every audit record into one large all-in-one audit table**.

Instead, the better first step is to audit each important area separately and organize the records by category.

This keeps the feature easier to understand, easier to build, and easier to review with advisers.

## Proposed Audit Categories

### Academic Periods

Tracks actions related to school years, semesters, and active semester changes.

Examples:

- Active semester changed.
- Semester settings updated.
- Academic period transition forced with a reason.

### Grade Center

Tracks important grading decisions and grade state changes.

Examples:

- Grade manually edited.
- Grade published.
- Grade finalized for archive.
- Stage or PIT event marked officially complete.
- Peer or adviser grading window changed.

### Scheduling

Tracks changes to defense schedules.

Examples:

- Schedule created.
- Schedule cancelled.
- Schedule marked done.
- Schedule deleted.
- Schedule status changed.

### Student Teams

Tracks important team-related changes.

Examples:

- Adviser changed.
- Team members changed.
- Team deleted or archived.
- Team status changed.

### Repository

Tracks repository and archive-related evidence.

Examples:

- Vault file uploaded.
- Vault file replaced.
- Repository entry status changed.
- Archive evidence updated.

### Guest Access

Tracks guest panelist code activity.

Examples:

- Guest code created.
- Guest code exchanged for access.
- Guest code used.
- Guest code revoked or expired.

## Proposed User Interface Direction

The screen can be called **Audit & Compliance Center**.

It should feel closer to an ISO-style audit dashboard than a developer log viewer.

Instead of showing raw technical records first, it should show:

- Audit readiness summary.
- Open findings or pending reviews.
- Verified evidence count.
- High-impact actions count.
- Audit categories.
- Evidence cards for selected records.

## Evidence Card Meaning

An evidence card is an audit-friendly summary of one important action.

Example:

**Evidence Card: Grade Publication**

- Control ID: `DEF-AC-013`
- Category: Grade Center
- Action: Grade was published
- Responsible user: Registrar/Admin
- Affected record: Team grade record
- Previous state: Pending
- New state: Published
- Reason: Final grade approved after review
- Evidence status: Captured
- Review status: Pending review
- Timestamp: Date and time of action

In simple terms, the evidence card acts like a receipt that proves what happened.

## Suggested Filters

The audit view should support filters so users do not need to search through every audit record manually.

Recommended filters:

- Category
- Date range
- Responsible user
- Action type
- Evidence status
- Review status
- Search by team, schedule, grade, file, or guest code

Category filter options:

- Academic Periods
- Grade Center
- Scheduling
- Student Teams
- Repository
- Guest Access

## Recommended Implementation Direction

### Step 1: Add Audit Logging Per Category

Add audit records to the existing high-impact workflows, one category at a time.

Priority order:

1. Academic Periods
2. Grade Center
3. Scheduling
4. Student Teams
5. Repository
6. Guest Access

### Step 2: Keep Existing Audit/History Records

The system already has some history or audit-like records.

Examples:

- Semester transition logs.
- Repository audit logs.
- Adviser assignment history.

These should not be removed. They can remain as category-specific history while the new audit evidence format is introduced gradually.

### Step 3: Add Category-Based Review Screens

Instead of building one giant audit table immediately, create category-based views or filters.

For example:

- Grade Center audit view.
- Schedule audit view.
- Repository evidence view.
- Guest access activity view.

The Audit & Compliance Center can later become the summary page that links to these category views.

### Step 4: Add Review Status

Audit records can have simple review states:

- Evidence captured
- Needs review
- Reviewed
- Requires reason

This makes the feature useful for adviser or administrator review, not just technical tracking.

## Why This Is Useful

This improves DefenSYS by making important actions traceable and reviewable.

Benefits:

- Helps explain who changed official academic data.
- Helps detect accidental or unauthorized changes.
- Supports adviser and administrator review.
- Makes repository, grading, scheduling, and access decisions easier to verify.
- Provides stronger evidence for future quality assurance or ISO-style review.

## Adviser Consultation Questions

Questions to confirm before implementation:

1. Which categories should be audited first?
2. Should audit review be limited to admins only, or also visible to PIT leads/advisers for their own scope?
3. Which actions should require a reason before saving?
4. Should the first version only capture evidence, or should it also include review/approval?
5. Should the Audit & Compliance Center be a summary dashboard first, with category-specific audit pages later?

## Recommended First Version

The recommended first version is:

- Add audit logging for the most important actions.
- Store each audit record with a category.
- Add filters by category.
- Keep the UI simple and adviser-friendly.
- Do not merge every audit feature into one large all-in-one system yet.

This approach gives DefenSYS stronger accountability while keeping the implementation manageable.
