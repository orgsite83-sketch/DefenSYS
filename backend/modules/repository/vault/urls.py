from django.urls import path

from .views import DigitalVaultListView, DigitalVaultSearchView


urlpatterns = [
    path('', DigitalVaultListView.as_view(), name='digital_vault'),
    path('search/', DigitalVaultSearchView.as_view(), name='digital_vault_search'),
]
