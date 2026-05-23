# DefenSYS system flow (single chart)

Visual map of the full DefenSYS workflow. For step-by-step prose, see [DEFENSYS_FLOW_OVERVIEW.md](DEFENSYS_FLOW_OVERVIEW.md). For API and screen details, see [DEFENSYS_REAL_SYSTEM_FLOW.md](DEFENSYS_REAL_SYSTEM_FLOW.md).

**How to read this chart:** Follow top to bottom. Diamonds are automatic decisions. Capstone team creation and phase are derived from the active semester (no manual Capstone phase control in Academic Periods).

```mermaid
flowchart TD
  subgraph auth [0_Login_and_routing]
    Login[User_logs_in]
    Login --> RoleCheck{Role?}
    RoleCheck -->|Admin| AdminShell[Admin_web_shell]
    RoleCheck -->|Faculty| FacultyGateway[Faculty_gateway]
    RoleCheck -->|Student| StudentApp[Student_mobile_app]
    RoleCheck -->|Guest_code| GuestPanelist[Guest_panelist_flow]
    FacultyGateway --> MultiRole{Multiple_faculty_roles?}
    MultiRole -->|yes| WorkspaceSwitch[Workspace_switcher]
    MultiRole -->|no| SingleWorkspace[Single_workspace]
    WorkspaceSwitch --> PitWS[PIT_Lead_workspace]
    WorkspaceSwitch --> AdvWS[Adviser_workspace]
    WorkspaceSwitch --> OtherWS[Panelist_Uploader_Repo_as_assigned]
  end

  subgraph setup [1_Academic_setup]
    AdminShell --> CreateSY[Admin_creates_SchoolYear]
    CreateSY --> CreateSem[Admin_adds_1st_and_2nd_Semesters]
    CreateSem --> ActivateOne[Admin_activates_one_semester]
    ActivateOne --> ActiveSem[Active_semester_gates_all_modules]
  end

  subgraph capstoneAuto [2_Capstone_calendar_automatic]
    ActiveSem --> SemLabel{Active_semester_label?}
    SemLabel -->|2nd_Semester| Cap1Phase[Capstone_1_intake]
    Cap1Phase --> Cap1Create[Admin_can_create_capstone_teams]
    SemLabel -->|1st_Semester| FourthYrTeams{4th_Year_capstone_teams_on_term?}
    FourthYrTeams -->|no| OffSeason[Off_season_no_capstone_create]
    FourthYrTeams -->|yes| Cap2Phase[Capstone_2_continue]
    Cap2Phase --> Cap2Manage[Manage_existing_teams_only]
    SemLabel -->|Summer| SummerOff[Summer_off_season]
    StudentRollover[Student_Records_rollover] --> PromoteRecords[Promote_retain_drop_per_student]
    PromoteRecords --> AdvanceCapTeams[Advance_3rd_Yr_Capstone_teams_to_4th_Yr]
    AdvanceCapTeams --> BumpToFirstSem[Teams_move_to_1st_Semester_record]
    BumpToFirstSem --> FourthYrTeams
  end

  subgraph records [3_Students_and_academic_records]
    ActiveSem --> ImportUsers[Admin_bulk_import_or_add_users]
    ImportUsers --> StudentBatch{Student_batch?}
    StudentBatch -->|yes| SetYearLevel[Set_year_level_and_semester_on_import]
    StudentBatch -->|no| FacultyImport[Faculty_general_import]
    SetYearLevel --> SAR[StudentAcademicRecord_per_semester]
    FacultyImport --> FacultyUsers[Faculty_user_accounts]
    SAR --> Eligibility[Team_and_capstone_eligibility_checks]
  end

  subgraph facultyAssign [4_Faculty_assignments]
    FacultyUsers --> AssignRoles[Assign_roles_per_semester_and_year]
    AssignRoles --> PitLeadRole[PIT_Lead_plus_pit_lead_year]
    AssignRoles --> AdviserRole[Project_Adviser]
    AssignRoles --> PanelRole[Panelist]
    AssignRoles --> RepoRole[Repo_assistant_optional]
    PitLeadRole --> PitWS
    AdviserRole --> AdvWS
    PanelRole --> GradeCenterEntry[Grade_Center_access]
  end

  subgraph pitPath [5_PIT_track]
    PitWS --> PitTeamsMgmt[Student_Teams_PIT_year_scoped]
    PitTeamsMgmt --> PitSchedule[Defense_Scheduler_PIT_events]
    PitSchedule --> PitBoard[Defense_Board]
    PitBoard --> PitGrades[Grade_Center_PIT_scope]
  end

  subgraph capstoneTeams [6_Capstone_teams]
    Cap1Create --> CreateTeam[Create_team_with_leader_members_adviser]
    CreateTeam --> TeamValidate[Validate_academic_records_and_year_level]
    TeamValidate --> TeamRow[Team_with_status_Pending]
    AdvWS --> AdviserHome[Adviser_dashboard_advised_teams]
    AdviserHome --> Deliverables[Capstone_Deliverables]
    AdviserHome --> WeeklyReports[Weekly_Progress_Reports]
    AdviserHome --> AdviserGradeNav[Grade_Students_adviser_path]
  end

  subgraph stagesRubrics [7_Defense_stages_and_rubrics]
    AdminShell --> ManageStages[Defense_Stages_admin]
    ManageStages --> RubricEngine[Rubric_Engine]
    RubricEngine --> RubricByType[Rubric_per_stage_and_type]
    RubricByType --> PanelRubric[evaluation_type_panel]
    RubricByType --> AdviserRubric[evaluation_type_adviser]
    RubricByType --> PeerRubric[evaluation_type_peer]
  end

  subgraph scheduling [8_Defense_scheduling]
    PitSchedule --> SchedForm[Choose_stage_or_PIT_event_rubric_date_panelists]
    TeamRow --> SchedForm
    Cap2Manage --> SchedForm
    SchedForm --> DefenseSched[Create_DefenseSchedule]
    DefenseSched --> LinkEval[Create_or_link_Evaluation]
    LinkEval --> FollowUpSetup[Follow_up_Setup_deadlines]
    FollowUpSetup --> AllowAdv[allow_adviser_grading]
    FollowUpSetup --> AllowPeer[allow_peer_evaluation]
  end

  subgraph liveDefense [9_Live_defense_and_matching]
    DefenseSched --> LiveWindow{Current_time_in_slot?}
    LiveWindow -->|before| NotStarted[Grading_Not_Started]
    LiveWindow -->|during| InProgress[Grading_In_Progress]
    LiveWindow -->|after| PastSlot[Past_slot]
    LinkEval --> MatchLogic[Evaluation_matches_schedule_and_team]
  end

  subgraph panelGrading [10_Panel_grading]
    GradeCenterEntry --> GradeCenter[Grade_Center_list]
    GradeCenter --> PanelSheet[Panel_grade_sheet]
    PanelSheet --> PanelDraft[Save_draft_scores]
    PanelSheet --> PanelPost[Post_panel_scores_locked]
    PanelPost --> GradingComplete{All_required_grading_done?}
    GradingComplete -->|yes| EvalComplete[Evaluation_Grading_Complete]
    EvalComplete --> SchedCompleted[DefenseSchedule_marked_Completed]
    SchedCompleted --> DefenseHistory[Moves_to_Defense_History]
  end

  subgraph adviserPeer [11_Adviser_and_peer_follow_up]
    AllowAdv --> AdviserGradeNav
    AdviserGradeNav --> AdviserRubricScores[Adviser_scores_via_standard_rubric]
    AdviserRubricScores --> AdviserTotal[Derived_adviser_total_stored]
    AllowPeer --> StudentApp
    StudentApp --> PeerFlow[Peer_evaluation_when_enabled]
    PeerFlow --> PeerRubricScores[Peer_scores_via_standard_rubric_Capstone]
  end

  subgraph summaryProgress [12_Grade_summary_and_progression]
    PanelPost --> GradeSummary[Grade_Summary]
    AdviserTotal --> GradeSummary
    PeerRubricScores --> GradeSummary
    GradeSummary --> WeightedOverall[Weighted_overall_grade]
    WeightedOverall --> PostedStage{Authoritative_posted_stage_score}
    PostedStage -->|at_least_75| TeamApproved[Team_status_Approved]
    PostedStage -->|below_75| TeamFailed[Team_status_Failed]
    TeamApproved --> NextStage[Eligible_for_next_defense_stage]
    TeamFailed --> Revise[Revisions_before_proceeding]
  end

  subgraph vault [13_Repository_and_vault]
    Deliverables --> SubmitDocs[Team_submits_deliverables]
    SubmitDocs --> RepoAudit[Repository_Audit_admin]
    RepoAudit --> VaultArchive[Approved_content_to_Digital_Vault]
    VaultArchive --> VaultBrowse[Students_and_faculty_browse_vault]
  end

  ActiveSem --> records
  Cap1Create --> capstoneTeams
  Cap2Manage --> capstoneTeams
  TeamRow --> stagesRubrics
  PanelRubric --> scheduling
  EvalComplete --> summaryProgress
  NextStage --> scheduling
```

## Legend

| Symbol | Meaning |
|--------|---------|
| Rectangle | Action or system state |
| Diamond | Automatic branch |
| Subgraph | Major module or phase of the system |

## Capstone vs PIT (quick reference)

| Calendar | PIT | Capstone |
|----------|-----|----------|
| 1st-2nd Year, both sems | PIT Lead manages PIT teams | Off-season for capstone admin |
| 3rd Year, 1st Sem | PIT (3rd Year) | Off-season; no new capstone teams |
| 3rd Year, 2nd Sem | PIT continues | **Capstone 1** — create teams, schedule, grade |
| 4th Year, 1st Sem | — | **Capstone 2** — same teams after rollover; no new intake |
| 4th Year, 2nd Sem+ | — | Continue or extended teams via rollover rules |

## Faculty workspaces (current UI)

| Workspace | Home focus | Typical nav |
|-----------|------------|-------------|
| PIT Lead | Year-scoped metrics and PIT teams | Teams, Scheduling, Grade Center, Rubrics |
| Adviser | Advised capstone teams | Deliverables, Weekly Reports, Grade Students |
| Panelist | Grade Center and assigned defenses | Via Grade Center / mobile panelist |

Workspaces are **not merged** on one dashboard; faculty with multiple roles use the workspace switcher.

## Status concepts (do not confuse)

| Concept | Used for | Examples |
|---------|----------|----------|
| Grading status | Evaluation workflow | Not Started, In Progress, Grading Complete |
| Team status | Stage progression gate | Pending, Approved, Failed |
| Schedule status | Defense event | Scheduled, Completed, Cancelled |

## Related implementation

- Capstone phase derivation: `backend/modules/academic_period_management/capstone_mode.py`
- Rollover team bump: `backend/modules/user_management/academic_records/views.py`
- Faculty workspaces: `frontend/lib/screens/web/faculty/faculty_dashboard.dart`
