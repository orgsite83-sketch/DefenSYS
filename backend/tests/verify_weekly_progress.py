"""
Verify Weekly Progress Report was added to all stages
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from defense_stages.models import DefenseStage, StageDeliverable

def verify_weekly_progress():
    print("\n" + "="*60)
    print("WEEKLY PROGRESS REPORT VERIFICATION")
    print("="*60)
    
    stages = DefenseStage.objects.filter(is_active=True).prefetch_related('deliverables')
    
    for stage in stages:
        print(f"\n📋 {stage.label}")
        print("-" * 60)
        
        deliverables = stage.deliverables.all().order_by('display_order')
        
        # Check if WPR exists
        wpr = deliverables.filter(deliverable_id='WPR').first()
        
        if wpr:
            print(f"✅ Weekly Progress Report FOUND")
            print(f"   - ID: {wpr.deliverable_id}")
            print(f"   - Label: {wpr.label}")
            print(f"   - Required: {wpr.required}")
            print(f"   - Type: {wpr.deliverable_type}")
            print(f"   - Display Order: {wpr.display_order}")
        else:
            print(f"❌ Weekly Progress Report NOT FOUND")
        
        print(f"\n   All deliverables ({deliverables.count()}):")
        for d in deliverables:
            icon = "📌" if d.required else "📄"
            type_label = "Pre-Defense" if d.deliverable_type == 'pre' else "Vault"
            print(f"   {icon} {d.deliverable_id}: {d.label} ({type_label})")
    
    print("\n" + "="*60)
    print("✅ VERIFICATION COMPLETE")
    print("="*60)
    
    # Summary
    total_stages = stages.count()
    stages_with_wpr = sum(1 for stage in stages if stage.deliverables.filter(deliverable_id='WPR').exists())
    
    print(f"\n📊 Summary:")
    print(f"   Total Active Stages: {total_stages}")
    print(f"   Stages with WPR: {stages_with_wpr}")
    
    if stages_with_wpr == total_stages:
        print(f"\n✅ SUCCESS: Weekly Progress Report added to all stages!")
    else:
        print(f"\n⚠️  WARNING: WPR missing from {total_stages - stages_with_wpr} stage(s)")
    
    print()

if __name__ == '__main__':
    verify_weekly_progress()
