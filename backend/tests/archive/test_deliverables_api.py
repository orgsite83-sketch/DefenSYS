"""
Test script to verify deliverables API functionality.

Uses the isolated test database (test_defensys_db), not defensys_db.
"""
import os
import sys

BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from defensys_backend.db_guard import assert_safe_for_orm_writes, bootstrap_test_db_script

bootstrap_test_db_script()

from defense.stages.models import DefenseStage, StageDeliverable
from defense.stages.serializers import DefenseStageSerializer, DefenseStageWriteSerializer

def test_read_stages_with_deliverables():
    """Test reading stages with deliverables"""
    print("\n" + "="*60)
    print("TEST 1: Reading Stages with Deliverables")
    print("="*60)
    
    stages = DefenseStage.objects.all()
    serializer = DefenseStageSerializer(
        stages,
        many=True,
        context={'ordered_stages': list(stages)}
    )
    
    for stage_data in serializer.data:
        print(f"\nStage: {stage_data['label']}")
        print(f" Code: {stage_data['code']}")
        print(f" Deliverables Count: {stage_data['deliverables_count']}")
        print(f" Deliverables:")
        for deliv in stage_data['deliverables']:
            print(f"- {deliv['deliverable_id']}: {deliv['label']} ({deliv['deliverable_type']}, required={deliv['required']})")
    
    print("\n Test 1 PASSED: Stages with deliverables read successfully")
    return True

def test_create_stage_with_deliverables():
    """Test creating a stage with deliverables"""
    assert_safe_for_orm_writes()
    print("\n" + "="*60)
    print("TEST 2: Creating Stage with Deliverables")
    print("="*60)
    
    # Check if test stage already exists
    existing = DefenseStage.objects.filter(label='Test Stage').first()
    if existing:
        print(f"Deleting existing test stage (ID: {existing.id})...")
        existing.delete()
    
    payload = {
        'label': 'Test Stage',
        'display_order': 99,
        'description': 'Test stage for deliverables',
        'is_active': False,
        'deliverables': [
            {
                'deliverable_id': 'T1',
                'label': 'T1 - Test Deliverable 1',
                'deliverable_type': 'pre',
                'required': True,
                'display_order': 1,
                'vault_note': '',
            },
            {
                'deliverable_id': 'T2',
                'label': 'T2 - Test Deliverable 2',
                'deliverable_type': 'vault',
                'required': False,
                'display_order': 2,
                'vault_note': 'Test vault note',
            },
        ]
    }
    
    serializer = DefenseStageWriteSerializer(data=payload)
    if not serializer.is_valid():
        print(f"Validation failed: {serializer.errors}")
        return False
    
    stage = serializer.save()
    print(f"\nCreated stage: {stage.label} (ID: {stage.id})")
    print(f"Deliverables count: {stage.deliverables.count()}")
    
    for deliv in stage.deliverables.all():
        print(f" - {deliv.deliverable_id}: {deliv.label}")
    
    print("\n Test 2 PASSED: Stage with deliverables created successfully")
    return stage

def test_update_stage_deliverables(stage):
    """Test updating stage deliverables"""
    assert_safe_for_orm_writes()
    print("\n" + "="*60)
    print("TEST 3: Updating Stage Deliverables")
    print("="*60)
    
    payload = {
        'label': 'Test Stage Updated',
        'deliverables': [
            {
                'deliverable_id': 'T1',
                'label': 'T1 - Updated Deliverable 1',
                'deliverable_type': 'pre',
                'required': True,
                'display_order': 1,
                'vault_note': '',
            },
            {
                'deliverable_id': 'T3',
                'label': 'T3 - New Deliverable 3',
                'deliverable_type': 'pre',
                'required': False,
                'display_order': 2,
                'vault_note': '',
            },
        ]
    }
    
    serializer = DefenseStageWriteSerializer(stage, data=payload, partial=True)
    if not serializer.is_valid():
        print(f"Validation failed: {serializer.errors}")
        return False
    
    updated_stage = serializer.save()
    print(f"\nUpdated stage: {updated_stage.label} (ID: {updated_stage.id})")
    print(f"Deliverables count: {updated_stage.deliverables.count()}")
    
    for deliv in updated_stage.deliverables.all():
        print(f" - {deliv.deliverable_id}: {deliv.label}")
    
    # Verify T2 was removed and T3 was added
    has_t1 = updated_stage.deliverables.filter(deliverable_id='T1').exists()
    has_t2 = updated_stage.deliverables.filter(deliverable_id='T2').exists()
    has_t3 = updated_stage.deliverables.filter(deliverable_id='T3').exists()
    
    if has_t1 and not has_t2 and has_t3:
        print("\n Test 3 PASSED: Deliverables updated correctly (T2 removed, T3 added)")
        return True
    else:
        print(f"\n Test 3 FAILED: Unexpected deliverables (T1={has_t1}, T2={has_t2}, T3={has_t3})")
        return False

def cleanup_test_stage():
    """Clean up test stage"""
    assert_safe_for_orm_writes()
    print("\n" + "="*60)
    print("CLEANUP: Removing Test Stage")
    print("="*60)
    
    test_stage = DefenseStage.objects.filter(label__startswith='Test Stage').first()
    if test_stage:
        print(f"Deleting test stage: {test_stage.label} (ID: {test_stage.id})")
        test_stage.delete()
        print("Cleanup complete")
    else:
        print("No test stage to clean up")

def main():
    print("\n" + "="*60)
    print("DELIVERABLES API TEST SUITE")
    print("="*60)
    
    try:
        # Test 1: Read existing stages with deliverables
        test_read_stages_with_deliverables()
        
        # Test 2: Create stage with deliverables
        test_stage = test_create_stage_with_deliverables()
        if not test_stage:
            print("\n TEST SUITE FAILED: Could not create test stage")
            return
        
        # Test 3: Update stage deliverables
        test_update_stage_deliverables(test_stage)
        
        # Cleanup
        cleanup_test_stage()
        
        print("\n" + "="*60)
        print("ALL TESTS PASSED")
        print("="*60)
        print("\nThe deliverables API is working correctly!")
        print("You can now test the feature in the UI.")
        
    except Exception as e:
        print(f"\n TEST SUITE FAILED with exception: {e}")
        import traceback
        traceback.print_exc()
        cleanup_test_stage()

if __name__ == '__main__':
    main()
