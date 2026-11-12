"""Read-only, batch identity review for uploaded timetable faculty references."""
from difflib import SequenceMatcher

from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from defensys_backend.read_projection import ReadAPIView
from defensys_backend.person_names import name_encoding_issue
from defensys_backend.person_matching import DEFAULT_PERSON_NAMES, PersonNameIndex
from authentication_access_control.scopes import is_admin_user, is_pit_lead_only
from user_management.permissions import CanManageModule
from .serializers import active_semester
from .event_scope import pit_events_for_user


class FacultyReferenceSerializer(serializers.Serializer):
    reference_id = serializers.CharField(max_length=250)
    duty = serializers.RegexField(r'^(chair|panel_[0-2]|documenter|adviser)$')
    text = serializers.CharField(max_length=250, allow_blank=True, trim_whitespace=False)
    selected_account_id = serializers.IntegerField(min_value=1, required=False, allow_null=True)


class ReferencePreviewSerializer(serializers.Serializer):
    revision = serializers.CharField(max_length=100)
    scope = serializers.ChoiceField(choices=['capstone', 'pit'])
    semester_id = serializers.IntegerField(min_value=1)
    defense_stage_id = serializers.IntegerField(min_value=1, required=False, allow_null=True)
    event_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    references = FacultyReferenceSerializer(many=True, max_length=3000)

    def validate_references(self, values):
        ids = [item['reference_id'] for item in values]
        if len(set(ids)) != len(ids):
            raise serializers.ValidationError('Reference IDs must be unique.')
        return values


def account_payload(account):
    return {'id': account.pk, 'username': account.username,
            'name': account.get_full_name().strip() or account.username,
            'is_active': account.is_active, 'is_panelist': account.is_panelist}


_REASONS = {
    'middle_initial_conflict': 'Middle initials conflict. Select the registered account.',
    'middle_initial_details': 'Middle-name details need confirmation.',
    'suffix_difference': 'Generational suffix differs or is omitted.',
    'surname_variant': 'Surname variant needs confirmation.',
    'name_details': 'Multiple compatible accounts. Select the registered ID.',
}


def preview_references(actor, data):
    semester = active_semester()
    if semester is None or semester.pk != data['semester_id']:
        raise serializers.ValidationError({'semester_id': 'Select the active semester and validate again.'})
    admin = is_admin_user(actor)
    if not admin and (data['scope'] != 'pit' or not is_pit_lead_only(actor)
                      or not getattr(actor, 'pit_lead_year', '')):
        raise PermissionDenied('This schedule scope is outside your assigned workspace.')
    if data['scope'] == 'pit':
        if any(ref['duty'] in ('documenter', 'adviser') for ref in data['references']):
            raise serializers.ValidationError({'references': 'PIT schedules do not assign documenters or advisers.'})
        event = data.get('event_name', '').strip()
        if event and not pit_events_for_user(actor, semester=semester).filter(event_name=event).exists():
            raise PermissionDenied('This PIT event is outside your assigned workspace.')
    elif data.get('defense_stage_id'):
        from defense.stages.models import DefenseStage
        if not DefenseStage.objects.filter(pk=data['defense_stage_id'], is_active=True).exists():
            raise serializers.ValidationError({'defense_stage_id': 'Select an active defense stage.'})

    # Inactive accounts remain in the identity index so filtering cannot hide a duplicate.
    users = list(get_user_model().objects.filter(role__in=['faculty', 'admin']).only(
        'id', 'username', 'first_name', 'last_name', 'role', 'is_active', 'is_panelist'))
    index = PersonNameIndex(users, DEFAULT_PERSON_NAMES)
    by_id = {u.pk: u for u in users}
    visible = [u for u in users if u.is_active]
    suggestion_cache = {}
    output = []
    for ref in data['references']:
        raw = ref['text']
        selected = ref.get('selected_account_id')
        result = index.resolve(raw, ['faculty', 'admin']) if not selected else None
        account = by_id.get(selected) if selected else result.user
        candidates = result.matches if result else ()
        state, reason = 'matched', ''
        kind = 'selected_id' if selected else result.kind
        if account is None:
            status = result.status if result else 'invalid_selection'
            state = ('encoding_problem' if status == 'encoding_problem' else 'needs_account'
                     if status in ('not_found', 'empty') else 'needs_confirmation')
            reason = ('Selected account is unavailable or has the wrong role.' if selected else
                      'Name encoding problem. Use an intact source or select the registered ID.'
                      if state == 'encoding_problem' else
                      'No matching account found. Verify the official ID or select an account.'
                      if state == 'needs_account' else
                      _REASONS.get(kind, 'Multiple or differing name details. Select the registered account.'))
        elif not account.is_active:
            state, reason = 'eligibility_issue', 'This account is inactive.'
        elif ref['duty'] in ('chair', 'panel_0', 'panel_1', 'panel_2') and not admin and not account.is_panelist:
            state, reason = 'eligibility_issue', 'Panelist approval is required before assignment.'

        # Suggestions never establish identity; only active directory-visible accounts are returned.
        if account is None and state != 'encoding_problem':
            key = DEFAULT_PERSON_NAMES.key(raw)
            if key not in suggestion_cache:
                ranked = sorted(((SequenceMatcher(None, key, DEFAULT_PERSON_NAMES.key(
                    u.get_full_name())).ratio(), u) for u in visible), key=lambda pair: (-pair[0], pair[1].pk))
                suggestion_cache[key] = [u for score, u in ranked[:8] if score >= 0.45]
            choices = list(candidates) + suggestion_cache[key]
        else:
            choices = list(candidates)
        seen, safe_choices = set(), []
        for candidate in choices:
            if candidate.is_active and candidate.pk not in seen:
                seen.add(candidate.pk)
                safe_choices.append(account_payload(candidate))
        warning = ''
        if account and (name_encoding_issue(account.first_name) or name_encoding_issue(account.last_name)):
            warning = 'Account name needs repair. Identity was selected by registered ID.'
        output.append({
            'reference_id': ref['reference_id'], 'text': raw, 'duty': ref['duty'],
            'reference_key': DEFAULT_PERSON_NAMES.key(raw), 'review_state': state,
            'reason': reason, 'match_kind': kind, 'identity_matched': account is not None,
            'account': account_payload(account) if account and account.is_active else None,
            'name_warning': warning, 'candidates': safe_choices[:8],
        })
    return {'revision': data['revision'], 'references': output}


class ScheduleImportReferencePreviewView(ReadAPIView):
    permission_classes = [CanManageModule]

    def post(self, request):
        serializer = ReferencePreviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(preview_references(request.user, serializer.validated_data))
