"""
Test script to verify that students only see their team's vault submissions
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam
from capstone_deliverables.models import DeliverableSubmission
from digital_vault.services import digital_vault_payload


class MockRequest:
    """Mock request object for testing"""
    def __init__(self, user):
        self.user = user
        self.query_params = {}


def test_student_vault_filtering():
    print("\n" + "="*80)
    print("TESTING STUDENT VAULT FILTERING")
    print("="*80)
    
    # Get a student user
    students = User.objects.filter(role='student')
    if not students.exists():
        print("❌ No students found in database")
        return
    
    student = students.first()
    print(f"\n✅ Testing with student: {student.username} ({student.first_name} {student.last_name})")
    
    # Get student's team(s)
    student_teams = StudentTeam.objects.filter(members=student)
    print(f"✅ Student is member of {student_teams.count()} team(s):")
    for team in student_teams:
        print(f"   - {team.name} (ID: {team.id})")
    
    # Get all vault submissions
    all_vault_submissions = DeliverableSubmission.objects.filter(
        deliverable_type=DeliverableSubmission.TYPE_VAULT
    )
    print(f"\n✅ Total vault submissions in database: {all_vault_submissions.count()}")
    
    # Get vault submissions for student's team(s)
    student_team_ids = list(student_teams.values_list('id', flat=True))
    student_vault_submissions = all_vault_submissions.filter(team_id__in=student_team_ids)
    print(f"✅ Vault submissions for student's team(s): {student_vault_submissions.count()}")
    
    if student_vault_submissions.exists():
        print("\n📄 Student's team vault submissions:")
        for sub in student_vault_submissions:
            print(f"   - {sub.file_name} (Team: {sub.team.name}, Stage: {sub.stage_label})")
    
    # Test the digital_vault_payload function
    print("\n" + "-"*80)
    print("TESTING digital_vault_payload() FUNCTION")
    print("-"*80)
    
    mock_request = MockRequest(student)
    payload = digital_vault_payload(mock_request)
    
    print(f"\n✅ Entries returned by API: {len(payload['entries'])}")
    print(f"✅ Counts: {payload['counts']}")
    
    if payload['entries']:
        print("\n📄 Entries visible to student:")
        for entry in payload['entries']:
            print(f"   - {entry['file_name']}")
            print(f"     Team: {entry['team_name']} (ID: {entry.get('team_id')})")
            print(f"     Type: {entry['type']}, Stage: {entry['stage']}")
            print(f"     Uploaded by: {entry['uploaded_by']}")
            print()
    
    # Verify filtering is working
    print("-"*80)
    print("VERIFICATION")
    print("-"*80)
    
    if not student_teams.exists():
        print("⚠️  Student is not in any team - should see 0 entries")
        if len(payload['entries']) == 0:
            print("✅ PASS: Student sees 0 entries (correct)")
        else:
            print(f"❌ FAIL: Student sees {len(payload['entries'])} entries (should be 0)")
    else:
        # Check that all returned entries belong to student's team
        all_correct = True
        for entry in payload['entries']:
            team_id = entry.get('team_id')
            if team_id not in student_team_ids:
                print(f"❌ FAIL: Entry '{entry['file_name']}' belongs to team {team_id}, not student's team")
                all_correct = False
        
        if all_correct:
            print("✅ PASS: All entries belong to student's team(s)")
        
        # Check that we're not missing any entries
        if len(payload['entries']) == student_vault_submissions.count():
            print("✅ PASS: Correct number of entries returned")
        else:
            print(f"⚠️  WARNING: Expected {student_vault_submissions.count()} entries, got {len(payload['entries'])}")
    
    print("\n" + "="*80)
    print("TEST COMPLETE")
    print("="*80 + "\n")


if __name__ == '__main__':
    test_student_vault_filtering()
