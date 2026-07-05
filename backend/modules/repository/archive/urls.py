from django.urls import path

from .views import ProjectArchiveListView, ProjectArchiveSearchView


urlpatterns = [
    path('', ProjectArchiveListView.as_view(), name='project_archive'),
    path('search/', ProjectArchiveSearchView.as_view(), name='project_archive_search'),
]
