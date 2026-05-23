from django.urls import include, path

urlpatterns = [
    path('stages/', include('defense.stages.urls')),
    path('schedules/', include('defense.scheduler.urls')),
    path('board/', include('defense.board.urls')),
]
