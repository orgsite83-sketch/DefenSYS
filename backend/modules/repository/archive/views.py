from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import (
    project_archive_payload,
    search_archive_payload,
    get_reviews_payload_for_target,
    save_user_review,
    delete_user_review,
    get_user_shelf_payload,
    update_user_shelf,
)


class ProjectArchiveListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(project_archive_payload(request))


class ProjectArchiveSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(search_archive_payload(request))


class RepositoryReviewView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        target_id = request.query_params.get('target_id', '').strip()
        if not target_id:
            return Response({'detail': 'target_id query param is required.'}, status=status.HTTP_400_BAD_REQUEST)
        return Response(get_reviews_payload_for_target(target_id, user=request.user))

    def post(self, request):
        target_id = request.data.get('target_id', '').strip()
        rating = request.data.get('rating', 5)
        remark = request.data.get('remark', '')

        if not target_id:
            return Response({'detail': 'target_id is required.'}, status=status.HTTP_400_BAD_REQUEST)

        payload = save_user_review(
            user=request.user,
            target_id=target_id,
            rating=rating,
            remark=remark,
        )
        return Response(payload, status=status.HTTP_200_OK)

    def delete(self, request):
        review_id = request.data.get('review_id') or request.query_params.get('review_id')
        if not review_id:
            return Response({'detail': 'review_id is required.'}, status=status.HTTP_400_BAD_REQUEST)

        success = delete_user_review(request.user, review_id)
        if success:
            return Response({'success': True}, status=status.HTTP_200_OK)
        return Response({'detail': 'Review not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)


class UserBookShelfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(get_user_shelf_payload(request.user))

    def post(self, request):
        target_id = request.data.get('target_id', '').strip()
        if not target_id:
            return Response({'detail': 'target_id is required.'}, status=status.HTTP_400_BAD_REQUEST)

        status_val = request.data.get('status')
        last_read_page = request.data.get('last_read_page')
        total_pages = request.data.get('total_pages')
        progress_percent = request.data.get('progress_percent')

        shelf_item = update_user_shelf(
            user=request.user,
            target_id=target_id,
            status=status_val,
            last_read_page=last_read_page,
            total_pages=total_pages,
            progress_percent=progress_percent,
        )
        return Response(shelf_item, status=status.HTTP_200_OK)

