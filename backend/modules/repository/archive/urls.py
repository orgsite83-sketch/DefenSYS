from django.urls import path

from .views import (
    ProjectArchiveListView,
    ProjectArchiveSearchView,
    RepositoryPreviewView,
    RepositoryReviewView,
    UserBookShelfView,
)


urlpatterns = [
    path('', ProjectArchiveListView.as_view(), name='project_archive'),
    path('search/', ProjectArchiveSearchView.as_view(), name='project_archive_search'),
    path('preview/', RepositoryPreviewView.as_view(), name='repository_preview'),
    path('reviews/', RepositoryReviewView.as_view(), name='repository_reviews'),
    path('shelf/', UserBookShelfView.as_view(), name='repository_shelf'),
]

