"""
URL configuration for defensys_backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include

from defensys_backend.media_views import AuthenticatedMediaFileView, PublicAvatarFileView
from defensys_backend.views import HealthCheckView
from authentication_access_control.password_reset import (
    ConfirmPasswordResetAPIView,
    RequestPasswordResetView,
    VerifyPasswordResetOTPView,
)

urlpatterns = [
    path('media/avatars/<path:file_path>', PublicAvatarFileView.as_view()),
    path('media/<path:file_path>', AuthenticatedMediaFileView.as_view()),
    path('admin/', admin.site.urls),
    path('api/health/', HealthCheckView.as_view(), name='health_check'),
    path('api/', include('authentication_access_control.urls')),
    path('api/dashboards/', include('dashboards.urls')),
    path('api/academic-periods/', include('academic_period_management.urls')),
    path('api/users/', include('user_management.urls')),
    path('api/teams/', include('student_teams.urls')),
    path('api/defense/', include('defense.urls')),
    path('api/grading/', include('grading.urls')),
    path('api/repository/', include('repository.urls')),
    path('api/curriculum-analytics/', include('curriculum_analytics.urls')),
    path('api/reports/', include('reports.urls')),
    path('api/notifications/', include('notifications.urls')),
    path(
        'api/media/files/<path:file_path>',
        AuthenticatedMediaFileView.as_view(),
        name='media_file_serve',
    ),
    # Password reset (6-digit OTP verification flow)
    path('api/password-reset/', RequestPasswordResetView.as_view(), name='password_reset_request'),
    path('api/password-reset/verify-otp/', VerifyPasswordResetOTPView.as_view(), name='password_reset_verify_otp'),
    path('api/password-reset/confirm/', ConfirmPasswordResetAPIView.as_view(), name='password_reset_confirm'),
]
