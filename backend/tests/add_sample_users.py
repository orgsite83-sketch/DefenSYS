import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User

# Sample users to create
users_data = [
    {
        'username': 'admin',
        'email': 'admin@defensys.com',
        'password': 'admin123',
        'first_name': 'System',
        'last_name': 'Administrator',
        'role': 'admin',
        'is_staff': True,
        'is_superuser': True,
    },
    {
        'username': 'student',
        'email': 'student@defensys.com',
        'password': 'student123',
        'first_name': 'John',
        'last_name': 'Doe',
        'role': 'student',
        'team_id': 'TEAM-001',
    },
    {
        'username': 'student2',
        'email': 'student2@defensys.com',
        'password': 'student123',
        'first_name': 'Jane',
        'last_name': 'Smith',
        'role': 'student',
        'team_id': 'TEAM-002',
    },
    {
        'username': 'faculty1',
        'email': 'faculty1@defensys.com',
        'password': 'faculty123',
        'first_name': 'Dr. Robert',
        'last_name': 'Johnson',
        'role': 'faculty',
        'is_panelist': True,
        'is_adviser': True,
        'adviser_phase': 'Capstone 1',
    },
    {
        'username': 'faculty2',
        'email': 'faculty2@defensys.com',
        'password': 'faculty123',
        'first_name': 'Prof. Maria',
        'last_name': 'Garcia',
        'role': 'faculty',
        'is_panelist': True,
    },
    {
        'username': 'faculty3',
        'email': 'faculty3@defensys.com',
        'password': 'faculty123',
        'first_name': 'Dr. Michael',
        'last_name': 'Chen',
        'role': 'faculty',
        'is_pit_lead': True,
        'pit_lead_year': '2026',
    },
]

print("Creating sample users...\n")

created_count = 0
updated_count = 0
skipped_count = 0

for user_data in users_data:
    username = user_data['username']
    password = user_data.pop('password')
    
    try:
        user, created = User.objects.get_or_create(
            username=username,
            defaults=user_data
        )
        
        if created:
            user.set_password(password)
            user.save()
            print(f"✓ Created: {username} ({user.role})")
            created_count += 1
        else:
            # Update existing user
            for key, value in user_data.items():
                setattr(user, key, value)
            user.set_password(password)
            user.save()
            print(f"↻ Updated: {username} ({user.role})")
            updated_count += 1
            
    except Exception as e:
        print(f"✗ Error creating {username}: {e}")
        skipped_count += 1

print(f"\n{'='*50}")
print(f"Summary:")
print(f"  Created: {created_count}")
print(f"  Updated: {updated_count}")
print(f"  Errors: {skipped_count}")
print(f"{'='*50}\n")

print("All users in database:")
print(f"{'Username':<15} {'Role':<10} {'Name':<25} {'Active'}")
print("-" * 60)
for u in User.objects.all().order_by('role', 'username'):
    full_name = f"{u.first_name} {u.last_name}"
    print(f"{u.username:<15} {u.role:<10} {full_name:<25} {u.is_active}")

print("\n" + "="*60)
print("Login Credentials:")
print("="*60)
print("Admin:")
print("  Username: admin | Password: admin123")
print("\nFaculty:")
print("  Username: faculty1 | Password: faculty123")
print("  Username: faculty2 | Password: faculty123")
print("  Username: faculty3 | Password: faculty123")
print("\nStudents:")
print("  Username: student | Password: student123")
print("  Username: student2 | Password: student123")
print("="*60)
