from django.urls import include, path

urlpatterns = [
    path('re-demos/', include('defense.redemo.urls')),
    path('stages/', include('defense.stages.urls')),
    path('schedules/', include('defense.scheduler.urls')),
    path('board/', include('defense.board.urls')),
    path('minutes/', include('defense.minutes.urls')),
]
