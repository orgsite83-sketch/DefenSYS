# Proposal: Implementing 'Both' (Team & Individual) Scoring Target

This document outlines the proposal to support a hybrid rubric containing both team-wide criteria (e.g., system prototype, team presentation) and individual student criteria (e.g., individual contribution, Q&A performance) in the same grading event.

---

## 1. Core Design: Criterion-Level Target Types

To enable grading at both levels simultaneously under one rubric, we will introduce a `target_type` field directly to individual criteria.

```
                  +-----------------------------+
                  |           Rubric            |
                  |  target_type: "both"        |
                  +--------------+--------------+
                                 |
           +---------------------+---------------------+
           |                                           |
+----------v------------------+             +----------v------------------+
|      RubricCriterion        |             |      RubricCriterion        |
|  name: "System Prototype"   |             |  name: "Individual Q&A"     |
|  target_type: "team"        |             |  target_type: "individual"  |
+-----------------------------+             +-----------------------------+
```

### Constraints and Validation:
1. **Rubric Target `team`**: All criteria under this rubric are automatically forced to `team`.
2. **Rubric Target `individual`**: All criteria under this rubric are automatically forced to `individual`.
3. **Rubric Target `both`**: Each criterion can be configured by the administrator as either `team` or `individual`.

---

## 2. Database Model & Schema Changes

### Backend models (`backend/modules/grading/rubrics/models.py`)

1. **`Rubric` Model**:
   Extend `TARGET_CHOICES` to include `both`:
   ```python
   TARGET_TEAM = 'team'
   TARGET_INDIVIDUAL = 'individual'
   TARGET_BOTH = 'both'
   
   TARGET_CHOICES = (
       (TARGET_TEAM, 'Team'),
       (TARGET_INDIVIDUAL, 'Individual'),
       (TARGET_BOTH, 'Both (Team & Individual)'),
   )
   ```

2. **`RubricCriterion` Model**:
   Add the `target_type` field:
   ```python
   target_type = models.CharField(
       max_length=20, 
       choices=TARGET_CHOICES, 
       default=TARGET_TEAM
   )
   ```
   Add clean validation:
   ```python
   def clean(self):
       # ...
       if self.rubric.target_type == Rubric.TARGET_TEAM and self.target_type != Rubric.TARGET_TEAM:
           self.target_type = Rubric.TARGET_TEAM
       elif self.rubric.target_type == Rubric.TARGET_INDIVIDUAL and self.target_type != Rubric.TARGET_INDIVIDUAL:
           self.target_type = Rubric.TARGET_INDIVIDUAL
   ```

---

## 3. API Payload & Validation (`PanelistGradeSubmissionView`)

When grading a rubric with `target_type == 'both'`, the client submits a list of submissions within a single HTTP POST request:
1. **Team-wide Submission**: Contains a single entry where `student_id = null`, containing only the scores matching the `team` criteria.
2. **Individual-student Submissions**: Contains N entries where `student_id` is set to the respective student's ID, containing only the scores matching the `individual` criteria.

### Backend Validation:
* If the submission has `student_id = None`, validate that the criteria scores exactly match the rubric's `team` criteria.
* If the submission has `student` set, validate that the criteria scores exactly match the rubric's `individual` criteria.

---

## 4. Grade Recalculation Service (`recompute_panel_score`)

When the rubric's `target_type == 'both'`, a student's total panel score from a panelist is the combined percentage of the team-wide criteria scores and their individual criteria scores.

$$\text{Panelist Percentage} = \frac{\sum \text{Team Criteria Scores} + \sum \text{Individual Criteria Scores}}{\sum \text{Team Criteria Max Scores} + \sum \text{Individual Criteria Max Scores}} \times 100$$

### Recalculation Logic:
1. Retrieve all submissions for the team grade.
2. For each student, group submissions by panelist/guest identifier.
3. For each panelist, retrieve their team submission (`student_id = null`) and the student's submission (`student_id = student.id`).
4. Merge the criterion scores, calculate the percentage, and save to `StudentStageGrade.panel_score`.

---

## 5. UI/UX Specifications

### Admin Rubric Editor (Web)
* Introduce the **Both** option in the **Scoring Target** dropdown.
* If **Both** is selected, display a dropdown column next to each criterion allowing selection of `Team` or `Individual`.

### Grader / Panelist Interface (Mobile & Web)
* **Team Section**: Shows team criteria fields at the top (graded once).
* **Individual Section**: Shows horizontal student chips/tabs. Selecting a student displays their specific individual criteria fields underneath.
