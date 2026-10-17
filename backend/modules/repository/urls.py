from django.urls import include, path

urlpatterns = [
    path('section-concepts/', include('repository.section_concepts.urls')),
    path('archive/', include('repository.archive.urls')),
    path('deliverables/', include('repository.deliverables.urls')),
    path('project-archive/', include('repository.project_archive.urls')),
    path('audit/', include('repository.project_archive.urls')),
]
