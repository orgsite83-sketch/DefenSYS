# Implementation Plan - Fix Peer Evaluation Toggle and Add PIT Config Save Button

This plan details how we will resolve the 500 Internal Server Error when toggling peer evaluation (caused by Redis/WebSocket channel layer connectivity errors in development), and introduce a "Save Event Config" button to persist the Vault File Template and grade weight configuration in the PIT scheduler.

## User Review Required

> [!WARNING]
> The WebSocket broadcast failure currently prevents toggling Peer Evaluation when Redis is offline. By wrapping the channel broadcast layer in a try-except block, the settings will save successfully even if the real-time push fails, and a warning will be logged on the backend.

> [!NOTE]
> The new "Save Event Config" button will allow users to persist PIT event configuration (such as weights, templates, and rubrics) directly to the database without needing to generate a schedule run first.

## Proposed Changes

---

### Backend Components

#### [MODIFY] [broadcast.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/realtime/broadcast.py)
- Wrap `async_to_sync(channel_layer.group_send)(group, message)` inside a `try...except Exception` block.
- Log a warning using Django/Python's standard `logging` module so that Redis/Channels downtime does not result in an HTTP 500 error.

#### [MODIFY] [views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py)
- In `PitEventConfigLookupView`, add a `post` handler:
  - Extract and validate parameters: `event_name`, `panel_rubric_id`, `peer_rubric_id`, `panel_weight`, `peer_weight`, `vault_file_template`, and optional `semester_id`.
  - Resolve the semester using `semester_id` or default to the active semester.
  - Query the database to retrieve `Rubric` instances matching `panel_rubric_id` and `peer_rubric_id`.
  - Invoke `upsert_pit_event_config` to save/update the config.
  - Return the updated configuration payload.

---

### Frontend Components

#### [MODIFY] [defense_scheduler_provider.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/services/defense_scheduler_provider.dart)
- Add a new action `savePitEventConfig(Map<String, dynamic> payload)` to the `DefenseSchedulerNotifier`:
  - Perform a `POST` request to `baseUrl + '/pit-event-config/'` with the encoded JSON payload.
  - Handle success and error states, setting the `isSaving`, `message`, or `error` state appropriately to trigger UI notifications.

#### [MODIFY] [defense_scheduler_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/defense_scheduler_screen.dart)
- Add a new method `Future<void> _savePitConfig()` in `_DefenseSchedulerScreenState`:
  - Gather and validate the input values: `event_name` (must not be empty), weights (must sum to 100%), and rubrics (must be selected).
  - Invoke `savePitEventConfig` via `ref.read(defenseSchedulerProvider.notifier)`.
- In `_buildStepOne`, add a "Save Event Config" button at the bottom of the PIT Setup Card (near the grade weight inputs):
  - Ensure the button has a premium modern style, showing an icon (e.g., `Icons.save_rounded`) and utilizing the application's color theme (`AppColors.maroon` / `AppColors.gold`).
  - Disable the button dynamically if inputs are invalid.

---

## Verification Plan

### Automated & Integration Tests
- Run backend unit tests to ensure `upsert_pit_event_config` works properly:
  ```bash
  python manage.py test modules.defense.scheduler
  ```

### Manual Verification
- **Test Peer Evaluation Toggle**:
  1. Navigate to the Grade Center page in the browser.
  2. Toggle "Peer grading open" for a PIT event.
  3. Verify that the request succeeds (no 500 error toast appears) and "Peer grading open" updates successfully, even if Redis is not running locally.
- **Test Save Event Config**:
  1. Navigate to the Defense Scheduler page.
  2. Fill out the "PIT event setup" section with a custom event name, template, rubrics, and weights.
  3. Click "Save Event Config".
  4. Verify the success toast appears.
  5. Refresh the page or search for the same event name to verify that the settings are successfully retrieved and pre-filled.
