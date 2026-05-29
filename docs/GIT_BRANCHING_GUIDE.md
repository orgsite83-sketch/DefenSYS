# Git Branching & Workflow Guide

This guide provides a simple, step-by-step workflow for creating a feature branch, working on your changes, and safely merging them back into the `main` branch.

---

## 1. Preparing the `main` Branch
Before starting any new work, always make sure your local `main` branch is clean and up-to-date with the remote server.

1. **Switch to the `main` branch:**
   ```bash
   git checkout main
   ```
2. **Download the latest changes from the remote repository:**
   ```bash
   git pull origin main
   ```

> [!TIP]
> Run `git status` to ensure you don't have any uncommitted changes from previous sessions before switching branches.

---

## 2. Creating and Switching to a New Branch
Create a descriptive branch name for the task you are working on (e.g., `feature/routing-fix`, `bugfix/auth-issue`, `docs/git-guide`).

1. **Create and switch to your new branch in one command:**
   ```bash
   git checkout -b <your-branch-name>
   ```
   *Example:* `git checkout -b feature/routing-fix`

2. **Verify that you are on the new branch:**
   ```bash
   git branch
   ```
   *(The active branch will have an asterisk `*` next to it.)*

---

## 3. Working and Committing Changes
Make your code edits as usual. Once you've reached a logical checkpoint:

1. **Check which files have been modified:**
   ```bash
   git status
   ```
2. **Add/Stage the modified files:**
   * To stage specific files:
     ```bash
     git add <path-to-file>
     ```
   * To stage all changed files:
     ```bash
     git add .
     ```
3. **Commit your changes with a clear message:**
   ```bash
   git commit -m "Brief description of the changes you made"
   ```

> [!NOTE]
> It is best practice to commit frequently with small, self-contained changes rather than one massive commit at the end.

---

## 4. Pushing and Merging Back to `main`

### Option A: Via Remote Repository & Pull Request (Recommended)
This is the standard professional workflow. It keeps a history of code reviews and runs automated tests if configured.

1. **Push your branch to the remote repository (GitHub, GitLab, etc.):**
   ```bash
   git push -u origin <your-branch-name>
   ```
   *(The `-u` flag sets the default upstream remote, so next time you can just type `git push`.)*
2. **Create a Pull Request (PR):**
   Go to your repository page (e.g., on GitHub) and click the **"Compare & pull request"** button that automatically appears, then merge it on the web interface once approved.

---

### Option B: Merging Locally (If you don't use Pull Requests)
If you want to merge your changes directly on your machine and push them straight to `main`:

1. **Switch back to the `main` branch:**
   ```bash
   git checkout main
   ```
2. **Pull any updates that might have been pushed while you were working:**
   ```bash
   git pull origin main
   ```
3. **Merge your feature branch into `main`:**
   ```bash
   git merge <your-branch-name>
   ```
4. **Push the merged changes to the remote repository:**
   ```bash
   git push origin main
   ```

---

## 5. Cleaning Up (Optional but Recommended)
Once your changes are successfully merged into `main`, you can clean up the temporary branch to keep your environment tidy.

1. **Delete the local branch:**
   ```bash
   git branch -d <your-branch-name>
   ```
2. **Delete the remote branch (if you pushed it to GitHub):**
   ```bash
   git push origin --delete <your-branch-name>
   ```

---

## Quick Reference Cheat Sheet

| Command | Action |
| :--- | :--- |
| `git status` | Check status of working directory (unstaged/staged files) |
| `git checkout main` | Switch to the `main` branch |
| `git pull origin main` | Update local `main` branch with latest remote changes |
| `git checkout -b <branch>` | Create and switch to a new branch |
| `git add <file>` | Stage a file to be committed |
| `git commit -m "<msg>"` | Save your staged changes with a commit message |
| `git push -u origin <branch>` | Push the branch to remote for the first time |
| `git merge <branch>` | Merge specified branch into the current active branch |
| `git branch -d <branch>` | Delete a local branch after merging it |
