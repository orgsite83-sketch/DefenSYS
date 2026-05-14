"""
Management command to create 40 student accounts - 10 students per year level
Run with: python manage.py create_40_students
"""

from django.core.management.base import BaseCommand
from authentication_access_control.models import User


class Command(BaseCommand):
    help = 'Create 40 student accounts - 10 per year level'

    def handle(self, *args, **options):
        """Create 40 students - 10 per year level"""
        
        year_levels = ['1st Year', '2nd Year', '3rd Year', '4th Year']
        students_created = 0
        students_updated = 0
        
        self.stdout.write("=" * 60)
        self.stdout.write("Creating 40 Student Accounts (10 per year level)")
        self.stdout.write("=" * 60)
        
        for year_index, year_level in enumerate(year_levels, start=1):
            self.stdout.write(f"\n📚 Creating {year_level} students...")
            
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
                    self.stdout.write(
                        self.style.SUCCESS(
                            f"  ✅ Created: {username} ({first_name} {last_name}) - {year_level}"
                        )
                    )
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
                    self.stdout.write(
                        self.style.WARNING(
                            f"  🔄 Updated: {username} ({first_name} {last_name}) - {year_level}"
                        )
                    )
        
        self.stdout.write("\n" + "=" * 60)
        self.stdout.write("📊 SUMMARY")
        self.stdout.write("=" * 60)
        self.stdout.write(f"✅ Students created: {students_created}")
        self.stdout.write(f"🔄 Students updated: {students_updated}")
        self.stdout.write(f"📝 Total students: {students_created + students_updated}")
        self.stdout.write("\n📋 Student Accounts by Year Level:")
        self.stdout.write("-" * 60)
        
        for year_index, year_level in enumerate(year_levels, start=1):
            start_num = (year_index - 1) * 10 + 1
            end_num = year_index * 10
            self.stdout.write(f"\n{year_level}:")
            self.stdout.write(f"  Username: student{start_num} to student{end_num}")
            self.stdout.write(f"  Email: student{start_num}@ustp.edu.ph to student{end_num}@ustp.edu.ph")
            self.stdout.write(f"  Password: student123 (all students)")
            self.stdout.write(f"  Names: Student{start_num} Year{year_index} to Student{end_num} Year{year_index}")
        
        self.stdout.write("\n" + "=" * 60)
        self.stdout.write("🔐 LOGIN CREDENTIALS")
        self.stdout.write("=" * 60)
        self.stdout.write("Username: student1 to student40")
        self.stdout.write("Password: student123")
        self.stdout.write("\n💡 TIP: You can now assign these students to teams!")
        self.stdout.write("=" * 60)
        
        self.stdout.write(
            self.style.SUCCESS(
                f"\n✅ Successfully created/updated {students_created + students_updated} student accounts!"
            )
        )
