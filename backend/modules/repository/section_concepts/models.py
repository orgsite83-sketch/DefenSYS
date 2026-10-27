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
    title_workflow_version = models.PositiveSmallIntegerField(default=1)
    shared_requirements_snapshot = models.JSONField(null=True, blank=True, default=None)
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

    def save(self, *args, **kwargs):
        if self._state.adding and self.shared_requirements_snapshot is None:
            from defense.shared_deliverables import shared_definitions
            self.shared_requirements_snapshot = shared_definitions(self.project.context)
        return super().save(*args, **kwargs)

    class Meta:
        app_label = 'repository'
        ordering = ['number', 'pk']
        constraints = [models.UniqueConstraint(fields=['project', 'number'], name='section_round_number_unique')]


class SectionSystemConcept(models.Model):
    title_review = models.JSONField(default=dict, blank=True)
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
    title_review_context = models.JSONField(default=dict, blank=True)
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


class SharedDeliverableSet(models.Model):
    """A context's captured shared requirements and participating project versions."""
    section = models.ForeignKey('student_teams.SectionAssignment', on_delete=models.PROTECT)
    defense_stage = models.ForeignKey('defense.DefenseStage', null=True, blank=True, on_delete=models.PROTECT)
    pit_event_config = models.ForeignKey('defense.PitEventGradingConfig', null=True, blank=True, on_delete=models.PROTECT)
    source_project = models.ForeignKey(SectionConceptProject, null=True, blank=True, on_delete=models.PROTECT)
    source_round = models.ForeignKey(SectionConceptRound, null=True, blank=True, on_delete=models.PROTECT)
    identity = models.CharField(max_length=64)
    requirements = models.JSONField(default=list)
    team_snapshot = models.JSONField(default=list)
    system_snapshot = models.JSONField(default=list)
    project_manager = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                       related_name='shared_deliverable_sets')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'repository'
        constraints = [
            models.CheckConstraint(condition=(models.Q(defense_stage__isnull=False, pit_event_config__isnull=True) |
                models.Q(defense_stage__isnull=True, pit_event_config__isnull=False)), name='shared_set_one_context'),
            models.UniqueConstraint(fields=['section', 'defense_stage', 'identity'], name='shared_set_stage_identity'),
            models.UniqueConstraint(fields=['section', 'pit_event_config', 'identity'], name='shared_set_event_identity'),
        ]


class SharedDeliverableFile(models.Model):
    title_review_context = models.JSONField(default=dict, blank=True)
    """Append-only files; section-wide and per-concept slots share one contract."""
    submission_set = models.ForeignKey(SharedDeliverableSet, on_delete=models.PROTECT, related_name='files')
    deliverable_id = models.CharField(max_length=40)
    slot_key = models.CharField(max_length=90)
    file = models.FileField(upload_to='shared_deliverables/%Y/%m/')
    file_name = models.CharField(max_length=255)
    file_size = models.PositiveBigIntegerField()
    revision = models.PositiveIntegerField(default=1)
    is_current = models.BooleanField(default=True)
    status = models.CharField(max_length=20, default='pending', choices=SectionConceptPaper._meta.get_field('status').choices)
    feedback = models.TextField(blank=True, default='')
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                    related_name='shared_deliverable_uploads')
    uploaded_at = models.DateTimeField(auto_now_add=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
                                    on_delete=models.PROTECT, related_name='shared_deliverable_reviews')
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        app_label = 'repository'
        constraints = [
            models.UniqueConstraint(fields=['submission_set', 'deliverable_id', 'slot_key'],
                condition=models.Q(is_current=True), name='shared_file_current_unique'),
            models.UniqueConstraint(fields=['submission_set', 'deliverable_id', 'slot_key', 'revision'],
                name='shared_file_revision_unique'),
        ]
