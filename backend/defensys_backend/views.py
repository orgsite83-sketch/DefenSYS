import logging
from django.db import connection
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from rest_framework import status

logger = logging.getLogger(__name__)


class HealthCheckView(APIView):
    """
    API endpoint that checks the health of the application,
    specifically verifying the database connection.
    """
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request, *args, **kwargs):
        health = {
            'status': 'healthy',
            'checks': {
                'database': 'healthy',
            }
        }
        status_code = status.HTTP_200_OK

        try:
            # Execute a simple query to verify database connectivity
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
        except Exception as e:
            logger.exception("Health check failed: database is unreachable.")
            health['status'] = 'unhealthy'
            health['checks']['database'] = f'unhealthy: {str(e)}'
            status_code = status.HTTP_503_SERVICE_UNAVAILABLE

        return Response(health, status=status_code)
