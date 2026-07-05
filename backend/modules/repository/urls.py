from django.urls import include, path

urlpatterns = [
    path('archive/', include('repository.archive.urls')),
    path('deliverables/', include('repository.deliverables.urls')),
    path('audit/', include('repository.audit.urls')),
]
