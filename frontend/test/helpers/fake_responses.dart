import 'dart:convert';

const teamsListJson = '''
{
  "teams": [
    {
      "id": 1,
      "name": "Team CodeLearners",
      "project_title": "Smart Campus Navigator",
      "year_level": "3rd Year",
      "level": "3rd Year Capstone",
      "status": "Pending",
      "leader_id": 10,
      "adviser_id": 5,
      "member_ids": [10, 11, 12, 13]
    }
  ],
  "students": [
    {"id": 10, "name": "Carlos Reyes", "username": "4081"}
  ],
  "advisers": [
    {"id": 5, "name": "Ricardo Fontanilla", "username": "206"}
  ],
  "levels": ["Capstone"],
  "statuses": ["Pending", "Approved"],
  "counts": {"total": 1}
}
''';

const teamDetailJson = '''
{
  "team": {
    "id": 1,
    "name": "Team CodeLearners",
    "project_title": "Smart Campus Navigator",
    "year_level": "3rd Year",
    "level": "3rd Year Capstone",
    "status": "Pending",
    "leader_id": 10,
    "adviser_id": 5,
    "member_ids": [10, 11]
  },
  "students": [
    {"id": 10, "name": "Carlos Reyes", "username": "4081"},
    {"id": 11, "name": "Maria Santos", "username": "4082"}
  ],
  "advisers": [
    {"id": 5, "name": "Ricardo Fontanilla", "username": "206"}
  ],
  "statuses": ["Pending", "Approved"]
}
''';

const loginSuccessJson = '''
{
  "access": "header.eyJleHAiOjk5OTk5OTk5OTl9.sig",
  "refresh": "test-refresh-token",
  "user": {
    "id": 1,
    "username": "admin",
    "role": "admin",
    "first_name": "Admin",
    "last_name": "User"
  }
}
''';

const dashboardAdminJson = '''
{
  "stats": {"total_teams": 1, "total_students": 40},
  "active_semester": "2026-2027"
}
''';

const deliverablesJson = '''
{
  "teams": [
    {
      "id": 1,
      "name": "Team CodeLearners",
      "stages": [
        {
          "stage_label": "Concept Proposal",
          "deliverables": [],
          "required_total": 6
        }
      ],
      "selected_stage": {
        "stage_label": "Concept Proposal",
        "deliverables": [],
        "required_total": 6
      }
    }
  ],
  "stage_options": ["Concept Proposal", "Project Proposal", "Final Defense"],
  "counts": {"teams": 1}
}
''';

const weeklyProgressJson = '''
{
  "reports": [
    {
      "id": 1,
      "team": 1,
      "week_number": 1,
      "report_date": "2026-05-10",
      "student_name": "Carlos Reyes"
    }
  ],
  "count": 1
}
''';

Map<String, dynamic> decodeJson(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;
