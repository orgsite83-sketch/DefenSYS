from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from django.core.exceptions import ValidationError as DjangoValidationError

from .peer_eval import submit_student_peer_evaluation


class PeerEvaluationSubmitSerializer(serializers.Serializer):
    teamId = serializers.IntegerField()
    evaluateeId = serializers.IntegerField()
    breakdown = serializers.ListField(child=serializers.DictField(), required=False, default=list)
    total = serializers.DecimalField(max_digits=7, decimal_places=2)
    max = serializers.DecimalField(max_digits=7, decimal_places=2)


class StudentPeerEvaluationSubmitView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = PeerEvaluationSubmitSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            payload = submit_student_peer_evaluation(
                evaluator=request.user,
                team_id=data['teamId'],
                evaluatee_id=data['evaluateeId'],
                breakdown=data.get('breakdown') or [],
                total=data['total'],
                max_score=data['max'],
            )
        except DjangoValidationError as exc:
            return Response(exc.message_dict if hasattr(exc, 'message_dict') else {'detail': exc.messages}, status=status.HTTP_400_BAD_REQUEST)

        return Response(payload, status=status.HTTP_200_OK)
