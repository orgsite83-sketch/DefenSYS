from django.core.management.base import BaseCommand
from authentication_access_control.models import User


class Command(BaseCommand):
    help = 'Create or update admin user with correct role'

    def handle(self, *args, **options):
        try:
            user = User.objects.get(username='admin')
            user.role = 'admin'
            user.is_staff = True
            user.is_superuser = True
            user.save()
            self.stdout.write(self.style.SUCCESS(
                f'Updated user: {user.username}, Role: {user.role}'
            ))
        except User.DoesNotExist:
            user = User.objects.create_superuser(
                username='admin',
                email='admin@defensys.com',
                password='admin123',
                role='admin'
            )
            self.stdout.write(self.style.SUCCESS(
                f'Created admin user: {user.username}, Role: {user.role}'
            ))
