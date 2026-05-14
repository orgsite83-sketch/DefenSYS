import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User

# Create or activate student account
try:
    user = User.objects.get(username='student')
    user.is_active = True
    user.save()
    print(f"✓ Activated existing student user: {user.username}")
except User.DoesNotExist:
    user = User.objects.create_user(
        username='student',
        email='student@defensys.com',
        password='student123',
        first_name='John',
        last_name='Doe',
        role='student',
        team_id='TEAM-001',
        is_active=True
    )
    print(f"✓ Created new student user: {user.username}")

print(f"\nStudent Account Details:")
print(f"  Username: student")
print(f"  Password: student123")
print(f"  Role: {user.role}")
print(f"  Team ID: {user.team_id}")
print(f"  Active: {user.is_active}")

print("\nAll users in database:")
for u in User.objects.all():
    print(f"  - {u.username}: role={u.role}, active={u.is_active}")
