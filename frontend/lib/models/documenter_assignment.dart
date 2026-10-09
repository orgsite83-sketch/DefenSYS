enum DocumenterFilter { today, needsAction, upcoming, records, all }

/// Display and queue rules shared by the web and phone documenter workspaces.
class DocumenterAssignment {
  const DocumenterAssignment(this.data);
  final Map<String, dynamic> data;

  static DateTime get manilaNow =>
      DateTime.now().toUtc().add(const Duration(hours: 8));
  int get id => (data['id'] as num).toInt();
  String get team => data['team_name']?.toString() ?? 'Team';
  String? get minutesStatus => data['minutes_status']?.toString();
  bool get cancelled => data['status'] == 'cancelled';
  bool get locked => cancelled || data['status'] == 'archived';
  bool get signed =>
      ['submitted', 'adviser_signed', 'completed'].contains(minutesStatus);
  bool get hasComments => data['minutes_has_comments'] == true;
  DateTime? get date =>
      DateTime.tryParse(data['scheduled_date']?.toString() ?? '');
  String get statusLabel => switch (minutesStatus) {
    'completed' => 'Finalized',
    'adviser_signed' => 'Awaiting chairman signature',
    'submitted' => 'Awaiting adviser signature',
    _ => hasComments ? 'Minutes in progress' : 'Minutes not started',
  };
  String get actionLabel => locked || signed
      ? (minutesStatus == 'completed' ? 'View signed PDF' : 'View minutes')
      : hasComments
      ? 'Continue minutes'
      : 'Start minutes';
  String get sessionLabel => switch (data['status']) {
    'done' => 'Session finished',
    'cancelled' => 'Cancelled',
    'archived' => 'Archived',
    _ => 'Scheduled',
  };

  bool matches(DocumenterFilter filter, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = date;
    return switch (filter) {
      DocumenterFilter.today => !locked && day == today,
      DocumenterFilter.needsAction =>
        !locked &&
            !signed &&
            (data['status'] == 'done' || (day != null && day.isBefore(today))),
      DocumenterFilter.upcoming => !locked && day != null && day.isAfter(today),
      DocumenterFilter.records => signed || (locked && minutesStatus != null),
      DocumenterFilter.all => true,
    };
  }

  static int chronological(DocumenterAssignment a, DocumenterAssignment b) =>
      '${a.data['scheduled_date']} ${a.data['start_time']}'.compareTo(
        '${b.data['scheduled_date']} ${b.data['start_time']}',
      );
}
