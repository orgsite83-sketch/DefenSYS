# Proposal: Enforcing Individual Target for Peer Rubrics

Peer evaluations in DefenSYS are designed to let students grade each of their teammates individually. Therefore, a Peer Evaluation rubric must **always** use the `individual` scoring target, rather than `team`. 

To prevent misconfiguration, we propose implementing validation and auto-enforcement at three levels: Database, Serializer, and Frontend.

---

## 1. Database Model Validation (`Rubric.clean`)

We can enforce this policy directly in the `Rubric` model's `clean` method in [rubrics/models.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/models.py). If a rubric is of type `peer`, its `target_type` is automatically forced to `individual` or raises a validation error if configured otherwise.

```python
    def clean(self):
        errors = {}
        # ... existing validations ...
        
        # Enforce peer evaluation to always be individual
        if self.evaluation_type == self.EVAL_PEER and self.target_type != self.TARGET_INDIVIDUAL:
            self.target_type = self.TARGET_INDIVIDUAL  # Auto-correct target type
            
        if errors:
            raise ValidationError(errors)
```

---

## 2. Serializer Validation (`RubricWriteSerializer`)

In [rubrics/serializers.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/serializers.py), we can force `target_type` to `individual` when saving or validating rubrics with evaluation type `peer`:

```python
    def validate(self, attrs):
        # ... existing validations ...
        
        if attrs.get('evaluation_type') == Rubric.EVAL_PEER:
            attrs['target_type'] = Rubric.TARGET_INDIVIDUAL
            
        return attrs
```

---

## 3. Frontend UI Behavior

In the Rubric Editor form inside the frontend application:
- When the user selects **Peer** as the evaluation type, the **Scoring Target** dropdown should be automatically selected as **Individual** and disabled (grayed out) to prevent user override.
- An explanatory caption can be displayed below it: *"Peer evaluations are always scored individually per student."*

---

## 4. Retroactive Database Cleanup (Optional Migration)

To ensure consistency in existing data, we can create a simple Django data migration that sets `target_type = 'individual'` for all existing rubrics where `evaluation_type = 'peer'`:

```python
from django.db import migrations

def force_peer_rubrics_to_individual(apps, schema_editor):
    Rubric = apps.get_model('grading', 'Rubric')
    Rubric.objects.filter(evaluation_type='peer').update(target_type='individual')

class Migration(migrations.Migration):
    dependencies = [
        # ... previous migration dependency ...
    ]
    operations = [
        migrations.RunPython(force_peer_rubrics_to_individual),
    ]
```
