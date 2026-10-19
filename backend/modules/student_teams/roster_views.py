from django.db import transaction
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from user_management.permissions import CanManageTeams
from defense.scheduler.models import PitEventGradingConfig
from .models import StudentTeam, PITSectionRoster
from .formation_access import require_formation_scope
from .term_scope import get_active_semester
from .pit_rosters import resolve, event_in_use, pin


class CurrentRosterView(APIView):
    permission_classes = [CanManageTeams]

    def scope(self, request, data):
        term = get_active_semester()
        if not term:
            raise ValidationError('No active semester is configured.')
        year, section = str(data.get('year_level', '')), str(data.get('section', ''))
        if year not in ('1st Year', '2nd Year', '3rd Year') or not section:
            raise ValidationError('Choose a PIT year and section.')
        require_formation_scope(request.user, term, f'{year} PIT', section)
        return term, year, section

    def get(self, request):
        term, year, section = self.scope(request, request.query_params)
        teams = StudentTeam.objects.filter(semester=term, year_level=year, section=section, level__icontains='PIT')
        return Response({'roster': resolve(term.pk, year).get(section), 'teams': [
            {'id': t.pk, 'name': t.name, 'event_name': t.current_defense_stage,
             'members': list(t.memberships.values_list('student_id', flat=True))} for t in teams]})

    @transaction.atomic
    def post(self, request):
        term, year, section = self.scope(request, request.data)
        ids = request.data.get('team_ids')
        if not isinstance(ids, list) or not ids or len(ids) > 500 or any(type(i) is not int for i in ids):
            raise ValidationError('Choose the complete current section roster.')
        teams = list(StudentTeam.objects.select_for_update().filter(pk__in=ids, semester=term,
            year_level=year, section=section, level__icontains='PIT'))
        if len(teams) != len(set(ids)):
            raise ValidationError('Some teams are outside this section and semester.')
        members = [s for t in teams for s in t.memberships.values_list('student_id', flat=True)]
        if len(members) != len(set(members)):
            raise ValidationError('A student appears in several selected teams. Choose one non-overlapping current roster.')
        previous = PITSectionRoster.objects.select_for_update().filter(
            semester=term, year_level=year, section=section).first()
        if previous and request.data.get('revision') != previous.revision:
            raise ValidationError('The current roster changed. Review its teams again.')
        # Freeze existing work before changing any legacy default inference.
        for event in PitEventGradingConfig.objects.select_for_update().filter(semester=term, year_level=year):
            old = resolve(term.pk, year, event.pk).get(section, {})
            if event_in_use(event, section) and old.get('team_ids'):
                pin(StudentTeam.objects.get(pk=old['team_ids'][0]), event)
        head, created = PITSectionRoster.objects.select_for_update().get_or_create(
            semester=term, year_level=year, section=section)
        head.teams.set(teams)
        head.revision += 1
        head.save(update_fields=['revision', 'updated_at'])
        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS, action='teams.current_roster',
            request=request, target=head, new_values={'team_ids': ids, 'revision': head.revision}, strict=True)
        return Response({'roster': resolve(term.pk, year)[section]})
