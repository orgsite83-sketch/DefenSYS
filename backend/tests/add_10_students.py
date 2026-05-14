import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User

# 10 students with different names
students_data = [
    {'username': 'student1', 'first_name': 'John', 'last_name': 'Doe', 'team_id': 'TEAM-001'},
    {'username': 'student2', 'first_name': 'Jane', 'last_name': 'Smith', 'team_id': 'TEAM-001'},
    {'username': 'student3', 'first_name': 'Michael', 'last_name': 'Johnson', 'team_id': 'TEAM-002'},
    {'username': 'student4', 'first_name': 'Emily', 'last_name': 'Williams', 'team_id': 'TEAM-002'},
    {'username': 'student5', 'first_name': 'David', 'last_name': 'Brown', 'team_id': 'TEAM-003'},
    {'username': 'student6', 'first_name': 'Sarah', 'last_name': 'Jones', 'team_id': 'TEAM-003'},
    {'username': 'student7', 'first_name': 'James', 'last_name': 'Garcia', 'team_id': 'TEAM-004'},
    {'username': 'student8', 'first_name': 'Maria', 'last_name': 'Martinez', 'team_id': 'TEAM-004'},
    {'username': 'student9', 'first_name': 'Robert', 'last_name': 'Rodriguez', 'team_id': 'TEAM-005'},
    {'username': 'student10', 'first_name': 'Lisa', 'last_name': 'Hernandez', 'team_id': 'TEAM-005'},
]

print("Creating 10 students...\n")

created_count = 0
updated_count = 0

for student_data in students_data:
    username = student_data['username']
    
    try:
        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'email': f'{username}@defensys.com',
                'first_name': student_data['first_name'],
                'last_name': student_data['last_name'],
                'role': 'student',
                'team_id': student_data['team_id'],
                'is_active': True,
            }
        )
        
        if created:
            user.set_password('student123')
            user.save()
            print(f"✓ Created: {username} - {student_data['first_name']} {student_data['last_name']} (Team: {student_data['team_id']})")
            created_count += 1
        else:
            # Update existing user
            user.first_name = student_data['first_name']
            user.last_name = student_data['last_name']
            user.role = 'student'
            user.team_id = student_data['team_id']
            user.set_password('student123')
            user.save()
            print(f"↻ Updated: {username} - {student_data['first_name']} {student_data['last_name']} (Team: {student_data['team_id']})")
            updated_count += 1
            
    except Exception as e:
        print(f"✗ Error creating {username}: {e}")

print(f"\n{'='*60}")
print(f"Summary:")
print(f"  Created: {created_count}")
print(f"  Updated: {updated_count}")
print(f"{'='*60}\n")

print("All students in database:")
print(f"{'Username':<12} {'Name':<25} {'Team':<12} {'Active'}")
print("-" * 60)
for u in User.objects.filter(role='student').order_by('username'):
    full_name = f"{u.first_name} {u.last_name}"
    print(f"{u.username:<12} {full_name:<25} {u.team_id or 'N/A':<12} {u.is_active}")

print("\n" + "="*60)
print("Login Credentials (All students):")
print("  Password: student123")
print("="*60)
