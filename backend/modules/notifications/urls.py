from django.urls import path
from .views import NotificationListView, NotificationReadView, NotificationReadAllView

urlpatterns = [
    path('', NotificationListView.as_view(), name='notification_list'),
    path('<int:pk>/read/', NotificationReadView.as_view(), name='notification_read'),
    path('<int:pk>/', NotificationReadView.as_view(), name='notification_detail'),
    path('read-all/', NotificationReadAllView.as_view(), name='notification_read_all'),
]
