import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User

# Check if admin exists
try:
    user = User.objects.get(username='admin')
    print(f"Found user: {user.username}")
    print(f"Current role: {user.role}")
    print(f"Is staff: {user.is_staff}")
    print(f"Is superuser: {user.is_superuser}")
    
    # Update to admin
    user.role = 'admin'
    user.is_staff = True
    user.is_superuser = True
    user.save()
    
    print("\n✓ Updated successfully!")
    print(f"New role: {user.role}")
    
except User.DoesNotExist:
    print("Admin user doesn't exist. Creating...")
    user = User.objects.create_superuser(
        username='admin',
        email='admin@defensys.com',
        password='admin123',
        first_name='Admin',
        last_name='User'
    )
    user.role = 'admin'
    user.save()
    print(f"✓ Created admin user with role: {user.role}")

print("\nAll users in database:")
for u in User.objects.all():
    print(f"  - {u.username}: role={u.role}")
