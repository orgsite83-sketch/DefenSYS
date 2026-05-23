"""
DEV ONLY — not for production deployment.

Creates prototype accounts student1–student40 with a shared dev password.
Use only on local/demo databases. See docs/DEPLOYMENT.md.
"""

import os

from django.core.management.base import BaseCommand

from authentication_access_control.models import User


class Command(BaseCommand):
    help = 'DEV ONLY: Create 40 prototype student accounts (student1–student40)'

    def handle(self, *args, **options):
        password = os.environ.get('DEFENSYS_DEV_STUDENT_PASSWORD', 'student123')
        self.stdout.write(self.style.WARNING('=' * 60))
        self.stdout.write(self.style.WARNING('DEV ONLY — do not run in production'))
        self.stdout.write(self.style.WARNING('=' * 60))

        year_levels = ['1st Year', '2nd Year', '3rd Year', '4th Year']
        students_created = 0
        students_updated = 0

        for year_index, year_level in enumerate(year_levels, start=1):
            for student_num in range(1, 11):
                overall_num = (year_index - 1) * 10 + student_num
                username = f'student{overall_num}'
                user, created = User.objects.get_or_create(
                    username=username,
                    defaults={
                        'email': f'{username}@ustp.edu.ph',
                        'first_name': f'Student{overall_num}',
                        'last_name': f'Year{year_index}',
                        'role': 'student',
                        'is_active': True,
                    },
                )
                user.email = f'{username}@ustp.edu.ph'
                user.first_name = f'Student{overall_num}'
                user.last_name = f'Year{year_index}'
                user.role = 'student'
                user.is_active = True
                user.set_password(password)
                user.save()
                if created:
                    students_created += 1
                else:
                    students_updated += 1

        self.stdout.write(
            self.style.SUCCESS(
                f'Done: {students_created} created, {students_updated} updated '
                f'(password from DEFENSYS_DEV_STUDENT_PASSWORD or default dev password).'
            )
        )
