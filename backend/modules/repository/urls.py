from django.urls import include, path

urlpatterns = [
    path('vault/', include('repository.vault.urls')),
    path('deliverables/', include('repository.deliverables.urls')),
    path('audit/', include('repository.audit.urls')),
]
