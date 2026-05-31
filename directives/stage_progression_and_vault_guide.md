# Guide: Stage Progression, Vault Deliverables, and Grade Center Configuration

This guide provides details on how the DefenSYS team lifecycle, defense stages, vault requirements, and Grade Center metrics are configured, explaining key behaviors and how to configure them.

---

## 1. Vault Deliverables & The "100%" Progress Bar

### What Causes "No Required Items"?
In the **Capstone Deliverables** screen, the Vault progress bar calculates completion using **required** vault items (`vault_required_uploaded` / `vault_required_total`).
* If a defense stage has no deliverables of type `Vault` configured in the database, OR
* If all configured vault deliverables for the stage are optional (i.e., the **Required** checkbox is unticked),

the system sets `vault_required_total` to `0` and displays:
`Vault — No required items` (instead of `100%`).

### How to Fix / Configure:
1. Log in as an **Administrator**.
2. Go to **Defense Stages** in the sidebar.
3. Click **Edit** next to the active stage (e.g., *Concept Proposal*, *Project Proposal*, or *Final Defense*).
4. Scroll down to the **Deliverables** section.
5. Click **Add deliverable** or edit an existing one:
   * Set **Type** to `Vault`.
   * Fill in the **Label** and **Vault File Template** (e.g., `{year}.{course}.{project}.{semester}.pdf`).
   * **Crucial Step**: Tick the **Required** checkbox.
6. Click **Save changes**. 
7. Once the defense is marked as done (which unlocks the vault) and students upload the files matching the template, the progress bar will display `100%`.

---

## 2. Stage Progression Workflow

### Is Stage Progression Automatic?
**No.** A student team does not automatically advance to the next defense stage (e.g., from *Concept Proposal* to *Project Proposal*) immediately after passing their defense. 

The progression is a **manual, workflow-driven process** designed around adviser endorsements and scheduling:

### How to Move a Team to the Next Stage:
1. **Switch Stage View**: In the **Capstone Deliverables** screen, the adviser or admin uses the **Stage View** dropdown to switch from the completed stage (e.g., *Concept Proposal*) to the next stage (e.g., *Project Proposal*).
2. **Submit Pre-Defense Requirements**: Under the new stage view, the team card will display the new pre-defense requirements. The team uploads the required files.
3. **Endorse the Team**: Once all required pre-defense deliverables are uploaded, the adviser or admin clicks **"Endorse"** on the team card.
4. **Official Backend Transition**: Clicking **Endorse** updates the team's `ready_for_stage` and `current_defense_stage` fields in the database to the new stage label.
5. **Scheduler and Defense**: The team will now appear in the **Defense Scheduler** under the new stage and can be scheduled for defense.

---

## 3. "0 Teams" in the Grade Center for a New Stage

### What Causes This?
In the **Grade Center**, the number of teams for a stage is calculated dynamically by counting the active evaluation grades (`TeamGrade` records) matching that stage label in the active term.
* When you create a new defense stage, no teams have been scheduled, endorsed, or graded for it yet.
* No `TeamGrade` records exist in the database for that stage.
* Therefore, the Grade Center displays **0 teams**.

### How to Fix / Populate:
This is normal behavior for a newly created stage. To populate teams in the Grade Center for the stage:
1. Complete the endorsement workflow for teams for that stage (as described in section 2).
2. Schedule defenses for the teams under the new stage. 
3. This creates the corresponding `TeamGrade` rows, and the team count in the Grade Center will immediately reflect the number of scheduled teams.

---

## 4. No Teams List in the Stage Deliverables Editor

### What Causes This?
When editing a defense stage (e.g., Admin -> Defense Stages -> Edit), you configure the **master template** of deliverables (requirements, weights, etc.) for that stage.
* This screen is a **global configuration editor** and does not manage individual teams.
* Thus, there is no teams list shown here.
* Once deliverables are saved on this template screen, they automatically apply to all Capstone teams when viewing them on the **Capstone Deliverables** screen under that stage view.
