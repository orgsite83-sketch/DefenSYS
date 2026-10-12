from django.conf import settings
from django.db import models

class DefenseMinutes(models.Model):
    STATUS_DRAFT = 'draft'
    STATUS_SUBMITTED = 'submitted'           # Documenter signed
    STATUS_ADVISER_SIGNED = 'adviser_signed'  # Adviser signed
    STATUS_COMPLETED = 'completed'            # Chairman signed — fully done

    STATUS_CHOICES = (
        (STATUS_DRAFT, 'Draft'),
        (STATUS_SUBMITTED, 'Submitted'),
        (STATUS_ADVISER_SIGNED, 'Adviser Signed'),
        (STATUS_COMPLETED, 'Completed'),
    )

    schedule = models.OneToOneField(
        'defense.DefenseSchedule',
        related_name='minutes',
        on_delete=models.CASCADE,
    )

    # Auto-filled from schedule (snapshotted for record integrity)
    team_name = models.CharField(max_length=120)
    project_title = models.CharField(max_length=255)
    adviser_name = models.CharField(max_length=160)
    defense_stage_label = models.CharField(max_length=120)
    defense_date = models.DateField()
    defense_time = models.TimeField()
    room = models.CharField(max_length=120)
    documenter_name = models.CharField(max_length=160)

    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DRAFT)

    # E-signatures (timestamped)
    documenter_signed_at = models.DateTimeField(null=True, blank=True)
    documenter_signed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_signed_as_documenter',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )
    adviser_signed_at = models.DateTimeField(null=True, blank=True)
    adviser_signed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_signed_as_adviser',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )
    chairman_signed_at = models.DateTimeField(null=True, blank=True)
    chairman_signed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_signed_as_chairman',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )

    # Generated PDF (after all signatures)
    pdf_file = models.FileField(upload_to='defense_minutes/', null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_minutes_defenseminutes'
        ordering = ['-created_at']

    def __str__(self):
        return f"Minutes for {self.team_name} - {self.defense_stage_label}"

    @property
    def current_panelist_comments(self):
        """Keep former comments as evidence without listing them on the current panel."""
        from .services import minutes_panel_roster

        panelist_ids = {assignment.panelist_id for assignment in self.schedule.panel_assignments.all()}
        guest_ids = {member['guest_invitation_id'] for member in minutes_panel_roster(self.schedule)
                     if member['guest_invitation_id'] is not None}
        return [comment for comment in self.panelist_comments.all()
                if (comment.guest_invitation_id in guest_ids if comment.guest_invitation_id is not None
                    else not panelist_ids or comment.panelist_id is None or comment.panelist_id in panelist_ids)]


class MinutesPanelistComment(models.Model):
    minutes = models.ForeignKey(
        DefenseMinutes,
        related_name='panelist_comments',
        on_delete=models.CASCADE,
    )
    panelist = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='minutes_comments_about',
        null=True, blank=True,
        on_delete=models.SET_NULL,
    )
    guest_invitation = models.ForeignKey(
        'user_management.GuestPanelistCode',
        related_name='minutes_comments_about',
        null=True, blank=True,
        on_delete=models.PROTECT,
    )
    panelist_name_snapshot = models.CharField(max_length=160)
    panelist_role_snapshot = models.CharField(max_length=40, blank=True)  # 'Chair', 'Panel Member 1', etc.
    comments = models.TextField(blank=True)
    display_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        db_table = 'defense_minutes_minutespanelistcomment'
        ordering = ['display_order', 'id']
        constraints = [
            models.UniqueConstraint(fields=['minutes', 'guest_invitation'],
                                    name='unique_minutes_guest_comment'),
            models.CheckConstraint(condition=models.Q(panelist__isnull=True) | models.Q(guest_invitation__isnull=True),
                                   name='minutes_comment_one_panelist_kind'),
        ]

    def __str__(self):
        return f"Comment by {self.panelist_name_snapshot} ({self.panelist_role_snapshot}) on {self.minutes}"


class DefenseMinutesRevision(models.Model):
    """Signed versions survive a reasoned amendment and remain downloadable."""
    minutes = models.ForeignKey(DefenseMinutes, on_delete=models.PROTECT, related_name='revisions')
    snapshot = models.JSONField()
    pdf_file = models.FileField(upload_to='defense_minutes/', null=True, blank=True)
    reason = models.TextField()
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'defense'
        ordering = ['-created_at', '-pk']
