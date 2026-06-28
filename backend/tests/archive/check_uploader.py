#!/usr/bin/env python
"""
Check uploader user configuration
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User

print("=" * 60)
print("UPLOADER USER CHECK")
print("=" * 60)

# Find all uploader users
uploaders = User.objects.filter(is_uploader=True)

if not uploaders.exists():
    print("\n No uploader users found!")
    print("\nTo create an uploader user:")
    print("1. Go to User Management in admin dashboard")
    print("2. Create or edit a faculty user")
    print("3. Check the 'Uploader' checkbox")
    print("4. Save the user")
else:
    print(f"\n Found {uploaders.count()} uploader user(s):\n")
    
    for user in uploaders:
        print(f"Username: {user.username}")
        print(f"Name: {user.first_name} {user.last_name}")
        print(f"Role: {user.role}")
        print(f"Is Uploader: {user.is_uploader}")
        print(f"Is Adviser: {user.is_adviser}")
        print(f"Is PIT Lead: {user.is_pit_lead}")
        print(f"Is Documenter: {user.is_documenter}")
        print(f"Is Panelist: {user.is_panelist}")
        
        # Check if ONLY uploader
        is_only_uploader = (
            user.is_uploader and
            not user.is_adviser and
            not user.is_pit_lead and
            not user.is_documenter
        )
        
        if is_only_uploader:
            print("This user is ONLY an uploader (will see dedicated dashboard)")
        else:
            print(" This user has multiple roles (will see sidebar)")
        
        print("-" * 60)

print("\n" + "=" * 60)
