"""
Script to create 40 student accounts - 10 students per year level
Run with: python manage.py shell < add_40_students.py
"""

import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User

def create_students():
    """Create 40 students - 10 per year level"""
    
    year_levels = ['1st Year', '2nd Year', '3rd Year', '4th Year']
    students_created = 0
    students_updated = 0
    
    print("=" * 60)
    print("Creating 40 Student Accounts (10 per year level)")
    print("=" * 60)
    
    for year_index, year_level in enumerate(year_levels, start=1):
        print(f"\n📚 Creating {year_level} students...")
        
        for student_num in range(1, 11):
            # Calculate overall student number (1-40)
            overall_num = (year_index - 1) * 10 + student_num
            
            username = f'student{overall_num}'
            email = f'student{overall_num}@ustp.edu.ph'
            first_name = f'Student{overall_num}'
            last_name = f'Year{year_index}'
            password = 'student123'  # Default password
            
            # Check if user already exists
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    'email': email,
                    'first_name': first_name,
                    'last_name': last_name,
                    'role': 'student',
                    'is_active': True,
                }
            )
            
            if created:
                user.set_password(password)
                user.save()
                students_created += 1
                print(f"  ✅ Created: {username} ({first_name} {last_name}) - {year_level}")
            else:
                # Update existing user
                user.email = email
                user.first_name = first_name
                user.last_name = last_name
                user.role = 'student'
                user.is_active = True
                user.set_password(password)
                user.save()
                students_updated += 1
                print(f"  🔄 Updated: {username} ({first_name} {last_name}) - {year_level}")
    
    print("\n" + "=" * 60)
    print("📊 SUMMARY")
    print("=" * 60)
    print(f"✅ Students created: {students_created}")
    print(f"🔄 Students updated: {students_updated}")
    print(f"📝 Total students: {students_created + students_updated}")
    print("\n📋 Student Accounts by Year Level:")
    print("-" * 60)
    
    for year_index, year_level in enumerate(year_levels, start=1):
        start_num = (year_index - 1) * 10 + 1
        end_num = year_index * 10
        print(f"\n{year_level}:")
        print(f"  Username: student{start_num} to student{end_num}")
        print(f"  Email: student{start_num}@ustp.edu.ph to student{end_num}@ustp.edu.ph")
        print(f"  Password: student123 (all students)")
        print(f"  Names: Student{start_num} Year{year_index} to Student{end_num} Year{year_index}")
    
    print("\n" + "=" * 60)
    print("🔐 LOGIN CREDENTIALS")
    print("=" * 60)
    print("Username: student1 to student40")
    print("Password: student123")
    print("\n💡 TIP: You can now assign these students to teams!")
    print("=" * 60)

if __name__ == '__main__':
    create_students()
