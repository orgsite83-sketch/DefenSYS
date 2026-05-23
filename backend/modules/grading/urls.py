from django.urls import include, path

urlpatterns = [
    path('rubrics/', include('grading.rubrics.urls')),
    path('grades/', include('grading.grades.urls')),
]
