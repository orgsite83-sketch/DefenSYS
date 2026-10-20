from django.conf import settings
from django.db import models


class SectionConceptProject(models.Model):
    section = models.ForeignKey('student_teams.SectionAssignment', on_delete=models.PROTECT,
                               related_name='concept_projects')
    defense_stage = models.ForeignKey('defense.DefenseStage', null=True, blank=True, on_delete=models.PROTECT)
    pit_event_config = models.ForeignKey('defense.PitEventGradingConfig', null=True, blank=True, on_delete=models.PROTECT)
    project_manager = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                       related_name='section_concept_projects')
    reviewer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                related_name='reviewed_section_concept_projects')
    title_mode = models.CharField(max_length=20, default='student_proposed',
                                 choices=[('student_proposed', 'Student proposed'), ('faculty_provided', 'Faculty provided')])
    created_at = models.DateTimeField(auto_now_add=True)

    @property
    def context(self):
        return self.pit_event_config or self.defense_stage

    class Meta:
        app_label = 'repository'
        constraints = [
            models.CheckConstraint(condition=(models.Q(defense_stage__isnull=False, pit_event_config__isnull=True) |
                models.Q(defense_stage__isnull=True, pit_event_config__isnull=False)), name='section_project_one_context'),
            models.UniqueConstraint(fields=['section', 'defense_stage'], name='section_project_stage_unique'),
            models.UniqueConstraint(fields=['section', 'pit_event_config'], name='section_project_event_unique'),
        ]


class SectionProjectTeam(models.Model):
    project = models.ForeignKey(SectionConceptProject, on_delete=models.CASCADE, related_name='team_links')
    team = models.ForeignKey('student_teams.StudentTeam', on_delete=models.PROTECT, related_name='section_project_links')
    project_version = models.PositiveIntegerField()

    class Meta:
        app_label = 'repository'
        constraints = [models.UniqueConstraint(fields=['project', 'team', 'project_version'], name='section_project_team_unique')]


class SectionConceptRound(models.Model):
    project = models.ForeignKey(SectionConceptProject, on_delete=models.PROTECT, related_name='rounds')
    number = models.PositiveIntegerField(default=1)
    selected_key = models.CharField(max_length=10, blank=True, default='')
    verdict = models.CharField(max_length=30, blank=True, default='')
    remarks = models.TextField(blank=True, default='')
    endorsed_at = models.DateTimeField(null=True, blank=True)
    endorsed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT,
                                   related_name='endorsed_section_rounds')
    endorsement_snapshot = models.JSONField(default=dict, blank=True)
    decision_snapshot = models.JSONField(default=dict, blank=True)
    decided_at = models.DateTimeField(null=True, blank=True)
    presentation_started_at = models.DateTimeField(null=True, blank=True)
    presentation_started_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.PROTECT, related_name='started_section_hearings')
    revisions_cleared_at = models.DateTimeField(null=True, blank=True)
    revisions_cleared_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.PROTECT, related_name='cleared_section_rounds')
    revision_notes = models.TextField(blank=True, default='')
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT,
                                  related_name='decided_section_rounds')
    chair = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT,
                              related_name='chaired_section_rounds')
    schedules = models.ManyToManyField('defense.DefenseSchedule', blank=True, related_name='section_concept_hearings')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'repository'
        ordering = ['number', 'pk']
        constraints = [models.UniqueConstraint(fields=['project', 'number'], name='section_round_number_unique')]


class SectionSystemConcept(models.Model):
    round = models.ForeignKey(SectionConceptRound, on_delete=models.PROTECT, related_name='systems')
    key = models.CharField(max_length=10)
    title = models.CharField(max_length=255, blank=True, default='')
    confirmed = models.BooleanField(default=False)
    decision = models.CharField(max_length=30, blank=True, default='')
    remarks = models.TextField(blank=True, default='')

    class Meta:
        app_label = 'repository'
        ordering = ['key']
        constraints = [models.UniqueConstraint(fields=['round', 'key'], name='section_system_key_unique')]


class SectionConceptAcknowledgment(models.Model):
    """An assigned faculty member's acknowledgment of one immutable shared version."""
    round = models.ForeignKey(SectionConceptRound, on_delete=models.PROTECT, related_name='acknowledgments')
    faculty = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                related_name='shared_concept_acknowledgments')
    fingerprint = models.CharField(max_length=64)
    snapshot = models.JSONField(default=dict)
    acknowledged_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'repository'
        constraints = [models.UniqueConstraint(fields=['round', 'faculty', 'fingerprint'],
            name='shared_acknowledgment_version_unique')]


class SectionConceptPaper(models.Model):
    concept = models.ForeignKey(SectionSystemConcept, on_delete=models.PROTECT, related_name='papers')
    purpose = models.CharField(max_length=10, default='proposal', choices=[('proposal', 'Proposal'), ('final', 'Approved concept paper')])
    file = models.FileField(upload_to='section_concepts/%Y/%m/')
    file_name = models.CharField(max_length=255)
    revision = models.PositiveIntegerField(default=1)
    is_current = models.BooleanField(default=True)
    status = models.CharField(max_length=20, default='pending', choices=[
        ('pending', 'Pending review'), ('accepted', 'Accepted'), ('rejected', 'Corrections requested')])
    feedback = models.TextField(blank=True, default='')
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='section_papers')
    uploaded_at = models.DateTimeField(auto_now_add=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT,
                                   related_name='reviewed_section_papers')
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        app_label = 'repository'
        constraints = [
            models.UniqueConstraint(fields=['concept', 'purpose'], condition=models.Q(is_current=True), name='section_paper_current_unique'),
            models.UniqueConstraint(fields=['concept', 'purpose', 'revision'], name='section_paper_revision_unique'),
        ]
