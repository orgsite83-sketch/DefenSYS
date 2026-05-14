from django.urls import path

from .views import DigitalVaultListView


urlpatterns = [
    path('', DigitalVaultListView.as_view(), name='digital_vault'),
]
