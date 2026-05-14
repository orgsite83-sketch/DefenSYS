from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from defense_stages.models import DefenseStage
from defense_stages.serializers import DefenseStageSerializer
from defensys_backend.prototype_tools import require_prototype_tools
from .models import Rubric
from .serializers import RubricSerializer, RubricWeightsSerializer, RubricWriteSerializer


class CanManageRubrics(BasePermission):
    message = 'Only administrators and PIT leads can manage rubrics.'

    def has_permission(self, request, view):
        return user_can_manage_rubrics(request.user)


def user_can_manage_rubrics(user):
    if not user or not user.is_authenticated:
        return False
    return bool(
        getattr(user, 'role', None) == 'admin'
        or user.is_superuser
        or getattr(user, 'is_pit_lead', False)
    )


def rubric_queryset_for_read(user):
    base = rubric_queryset()
    if user_can_manage_rubrics(user):
        return base
    return base.filter(status=Rubric.STATUS_PUBLISHED)


def rubric_queryset():
    return (
        Rubric.objects.select_related(
            'semester',
            'semester__school_year',
            'defense_stage',
            'created_by',
        )
        .prefetch_related('criteria')
    )


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def options_payload():
    semesters = Semester.objects.select_related('school_year').order_by('-school_year__label', 'label')
    stages = DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label')
    return {
        'active_semester': SemesterSerializer(active_semester()).data if active_semester() else None,
        'semesters': SemesterSerializer(semesters, many=True).data,
        'defense_stages': DefenseStageSerializer(stages, many=True).data,
        'scopes': [
            {'value': key, 'label': label}
            for key, label in Rubric.SCOPE_CHOICES
        ],
        'evaluation_types': [
            {'value': key, 'label': label}
            for key, label in Rubric.EVALUATION_TYPE_CHOICES
        ],
        'scale_options': [choice[0] for choice in Rubric.SCALE_CHOICES],
        'statuses': [choice[0] for choice in Rubric.STATUS_CHOICES],
        'default_weights': {
            'capstone': {'panel': 50, 'adviser': 30, 'peer': 20},
            'pit': {'panel': 80, 'adviser': 0, 'peer': 20},
        },
    }


def counts_payload(queryset=None, stats_base=None):
    base = stats_base if stats_base is not None else rubric_queryset()
    current = queryset if queryset is not None else base
    return {
        'all': base.count(),
        'filtered': current.count(),
        'draft': current.filter(status=Rubric.STATUS_DRAFT).count(),
        'published': current.filter(status=Rubric.STATUS_PUBLISHED).count(),
        'locked': current.filter(is_locked=True).count(),
        'capstone': current.filter(scope=Rubric.SCOPE_CAPSTONE).count(),
        'pit': current.filter(scope=Rubric.SCOPE_PIT).count(),
    }


def list_payload(queryset=None, stats_base=None):
    current = queryset if queryset is not None else rubric_queryset()
    base = stats_base if stats_base is not None else rubric_queryset()
    return {
        'rubrics': RubricSerializer(current, many=True).data,
        'counts': counts_payload(current, stats_base=base),
        **options_payload(),
    }


def filter_rubrics(request, queryset=None):
    queryset = queryset if queryset is not None else rubric_queryset()
    search = request.query_params.get('search', '').strip()
    scope = request.query_params.get('scope', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    evaluation_type = request.query_params.get('evaluation_type', '').strip()

    if search:
        queryset = queryset.filter(
            Q(name__icontains=search)
            | Q(event_name__icontains=search)
            | Q(defense_stage__label__icontains=search)
            | Q(semester__school_year__label__icontains=search)
            | Q(semester__label__icontains=search)
        )
    if scope:
        queryset = queryset.filter(scope=scope)
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    if evaluation_type:
        queryset = queryset.filter(evaluation_type=evaluation_type)
    return queryset


class RubricListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [CanManageRubrics()]

    def get(self, request):
        visible = rubric_queryset_for_read(request.user)
        filtered = filter_rubrics(request, visible)
        return Response(list_payload(filtered, stats_base=visible))

    def post(self, request):
        serializer = RubricWriteSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        rubric = serializer.save()
        rubric = rubric_queryset().get(pk=rubric.pk)
        return Response(
            {
                'rubric': RubricSerializer(rubric).data,
                **list_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


class RubricDetailView(APIView):
    permission_classes = [CanManageRubrics]

    def get_object(self, rubric_id):
        return get_object_or_404(rubric_queryset(), pk=rubric_id)

    def patch(self, request, rubric_id):
        rubric = self.get_object(rubric_id)
        serializer = RubricWriteSerializer(
            rubric,
            data=request.data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        rubric = serializer.save()
        rubric = rubric_queryset().get(pk=rubric.pk)
        return Response({
            'rubric': RubricSerializer(rubric).data,
            **list_payload(),
        })

    def delete(self, request, rubric_id):
        rubric = self.get_object(rubric_id)
        rubric.delete()
        return Response(list_payload(), status=status.HTTP_200_OK)


class RubricPublishView(APIView):
    permission_classes = [CanManageRubrics]

    def post(self, request, rubric_id):
        rubric = get_object_or_404(rubric_queryset(), pk=rubric_id)
        if rubric.criteria.count() == 0:
            return Response(
                {'criteria': 'At least one criterion is required before publishing.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        rubric.status = Rubric.STATUS_PUBLISHED
        rubric.is_locked = True
        rubric.save()
        rubric = rubric_queryset().get(pk=rubric.pk)
        return Response({
            'rubric': RubricSerializer(rubric).data,
            **list_payload(),
        })


class RubricWeightsView(APIView):
    permission_classes = [CanManageRubrics]

    def patch(self, request, rubric_id):
        rubric = get_object_or_404(rubric_queryset(), pk=rubric_id)
        serializer = RubricWeightsSerializer(
            data=request.data,
            context={'rubric': rubric},
        )
        serializer.is_valid(raise_exception=True)
        rubric = serializer.save()
        rubric = rubric_queryset().get(pk=rubric.pk)
        return Response({
            'rubric': RubricSerializer(rubric).data,
            **list_payload(),
        })


class RubricSeedDemoView(APIView):
    permission_classes = [CanManageRubrics]

    def post(self, request):
        require_prototype_tools()
        semester = active_semester()
        if semester is None:
            return Response(
                {'semester_id': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        stages = {
            stage.label: stage
            for stage in DefenseStage.objects.filter(
                label__in=['Project Proposal', 'Final Defense'],
                is_active=True,
            )
        }
        missing = [label for label in ['Project Proposal', 'Final Defense'] if label not in stages]
        if missing:
            return Response(
                {'defense_stage_id': f'Missing active stages: {", ".join(missing)}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        created = []
        skipped = 0
        for seed in seed_rubrics():
            stage = stages[seed['stage']]
            if Rubric.objects.filter(semester=semester, name__iexact=seed['name']).exists():
                skipped += 1
                continue
            serializer = RubricWriteSerializer(
                data={
                    'name': seed['name'],
                    'scope': Rubric.SCOPE_CAPSTONE,
                    'semester_id': semester.id,
                    'defense_stage_id': stage.id,
                    'evaluation_type': seed['evaluation_type'],
                    'scale': seed['scale'],
                    'status': Rubric.STATUS_PUBLISHED,
                    'criteria': seed['criteria'],
                },
                context={'request': request},
            )
            serializer.is_valid(raise_exception=True)
            created.append(serializer.save())

        return Response({
            'created': RubricSerializer(rubric_queryset().filter(pk__in=[item.pk for item in created]), many=True).data,
            'created_count': len(created),
            'skipped_count': skipped,
            **list_payload(),
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


def seed_rubrics():
    return [
        {
            'name': 'Project Proposal - Panel Rubric',
            'stage': 'Project Proposal',
            'evaluation_type': Rubric.EVAL_PANEL,
            'scale': Rubric.SCALE_10,
            'criteria': panel_criteria(),
        },
        {
            'name': 'Project Proposal - Adviser Rubric',
            'stage': 'Project Proposal',
            'evaluation_type': Rubric.EVAL_ADVISER,
            'scale': Rubric.SCALE_10,
            'criteria': adviser_criteria(),
        },
        {
            'name': 'Project Proposal - Peer Rubric',
            'stage': 'Project Proposal',
            'evaluation_type': Rubric.EVAL_PEER,
            'scale': Rubric.SCALE_5,
            'criteria': peer_criteria(),
        },
        {
            'name': 'Final Defense - Panel Rubric',
            'stage': 'Final Defense',
            'evaluation_type': Rubric.EVAL_PANEL,
            'scale': Rubric.SCALE_10,
            'criteria': panel_criteria(final=True),
        },
        {
            'name': 'Final Defense - Adviser Rubric',
            'stage': 'Final Defense',
            'evaluation_type': Rubric.EVAL_ADVISER,
            'scale': Rubric.SCALE_10,
            'criteria': adviser_criteria(final=True),
        },
        {
            'name': 'Final Defense - Peer Rubric',
            'stage': 'Final Defense',
            'evaluation_type': Rubric.EVAL_PEER,
            'scale': Rubric.SCALE_5,
            'criteria': peer_criteria(),
        },
    ]


def panel_criteria(final=False):
    names = [
        'System Functionality' if final else 'Research Significance',
        'Technical Depth' if final else 'Methodology and Design',
        'Innovation and Originality' if final else 'Technical Feasibility',
        'Presentation and Delivery',
        'Question and Answer Response',
    ]
    return [
        criterion_payload(name, Rubric.SCALE_10, 10, index)
        for index, name in enumerate(names)
    ]


def adviser_criteria(final=False):
    names = [
        'Research Completeness' if final else 'Research Quality',
        'Technical Achievement' if final else 'Student Progress',
        'Documentation Quality' if final else 'Documentation',
    ]
    return [
        criterion_payload(name, Rubric.SCALE_10, 10, index)
        for index, name in enumerate(names)
    ]


def peer_criteria():
    names = [
        'Teamwork and Collaboration',
        'Contribution to Project',
        'Communication',
    ]
    return [
        criterion_payload(name, Rubric.SCALE_5, 5, index)
        for index, name in enumerate(names)
    ]


def criterion_payload(name, scale, max_score, index):
    return {
        'name': name,
        'description': '',
        'scale': scale,
        'max_score': max_score,
        'weight': 1,
        'display_order': index,
    }
