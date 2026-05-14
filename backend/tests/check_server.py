#!/usr/bin/env python
"""
Check if server is configured correctly
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.urls import get_resolver
from django.conf import settings

print("=" * 60)
print("SERVER CONFIGURATION CHECK")
print("=" * 60)

print(f"\n📍 Allowed Hosts: {settings.ALLOWED_HOSTS}")
print(f"🔧 Debug Mode: {settings.DEBUG}")

print("\n📋 Registered URL Patterns:")
resolver = get_resolver()
for pattern in resolver.url_patterns:
    if hasattr(pattern, 'pattern'):
        print(f"   - {pattern.pattern}")

print("\n✅ Expected endpoint: http://10.86.31.199:8000/api/teams/")
print("\n⚠️  Make sure to run:")
print("   python manage.py runserver 10.86.31.199:8000")

print("\n" + "=" * 60)
