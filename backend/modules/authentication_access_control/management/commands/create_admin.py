import os

from django.core.management.base import BaseCommand, CommandError

from authentication_access_control.models import User


class Command(BaseCommand):
    help = 'Create or update the bootstrap admin superuser from environment variables'

    def handle(self, *args, **options):
        username = os.environ.get('DJANGO_SUPERUSER_USERNAME', 'admin').strip()
        email = os.environ.get('DJANGO_SUPERUSER_EMAIL', 'admin@defensys.local').strip()
        password = os.environ.get('DJANGO_SUPERUSER_PASSWORD', '').strip()

        if not username:
            raise CommandError('DJANGO_SUPERUSER_USERNAME must not be empty.')

        try:
            user = User.objects.get(username=username)
            user.role = 'admin'
            user.is_staff = True
            user.is_superuser = True
            if email:
                user.email = email
            if password:
                user.set_password(password)
            user.save()
            self.stdout.write(self.style.SUCCESS(f'Updated admin user: {user.username}'))
            if not password:
                self.stdout.write(
                    self.style.WARNING('Password unchanged (set DJANGO_SUPERUSER_PASSWORD to rotate).')
                )
            return
        except User.DoesNotExist:
            pass

        if not password:
            raise CommandError(
                'Set DJANGO_SUPERUSER_PASSWORD before creating the bootstrap admin user.'
            )

        user = User.objects.create_superuser(
            username=username,
            email=email,
            password=password,
            role='admin',
        )
        self.stdout.write(self.style.SUCCESS(f'Created admin user: {user.username}'))
