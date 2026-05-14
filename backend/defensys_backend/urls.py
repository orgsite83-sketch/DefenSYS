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
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('authentication_access_control.urls')),
    path('api/dashboards/', include('dashboards.urls')),
    path('api/academic-periods/', include('academic_period_management.urls')),
    path('api/users/', include('user_management.urls')),
    path('api/student-records/', include('student_academic_records.urls')),
    path('api/teams/', include('student_teams.urls')),
    path('api/defense-stages/', include('defense_stages.urls')),
    path('api/rubrics/', include('rubric_engine.urls')),
    path('api/defense-schedules/', include('defense_scheduler.urls')),
    path('api/defense-board/', include('defense_board.urls')),
    path('api/grade-center/', include('grade_center.urls')),
    path('api/capstone-deliverables/', include('capstone_deliverables.urls')),
    path('api/digital-vault/', include('digital_vault.urls')),
    path('api/repository-audit/', include('repository_audit.urls')),
    path('api/curriculum-analytics/', include('curriculum_analytics.urls')),
    path('api/weekly-progress/', include('student_weekly_progress.urls')),
]

# Add team documents URL
urlpatterns.append(path('api/documents/', include('team_documents.urls')))

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
