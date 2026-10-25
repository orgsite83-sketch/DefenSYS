"""Simulate assigned faculty's Review & Endorse action for demo deliverables.

From execution/: python auto_review_endorse.py --all-teams --year 1 --dry-run
Remove --dry-run to accept the scheduling files and endorse eligible teams.
Add --timing post to accept/archive post-defense files without endorsement.
All writes use the existing faculty API; local Django access is read-only.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
import sys

if __package__:
    from . import upload_deliverables as common
else:
    import upload_deliverables as common


def discover_reviewers(*, scope, stage, year=None, team_ids=None, reviewers=None):
    """Find real assignments in the active term; never fall back to an admin."""
    with common.local_read_only():
        from academic_period_management.models import Semester
        from student_teams.models import StudentTeam
        from authentication_access_control.workspaces import workspace_teams_for
        from user_management.models import SectionInstructorAssignment

        terms = list(Semester.objects.filter(is_active=True))
        if len(terms) != 1:
            raise common.UploadError('Exactly one active semester is required.')
        term = terms[0]
        teams = StudentTeam.objects.filter(semester=term,
            level__icontains='PIT' if scope == 'pit' else 'Capstone')
        if year:
            teams = teams.filter(year_level=year)
        if team_ids is not None:
            teams = teams.filter(pk__in=team_ids)
        if scope == 'pit':
            from defense.scheduler.models import PitEventGradingConfig
            from student_teams.pit_rosters import filter_teams
            event = PitEventGradingConfig.objects.filter(semester=term, event_name=stage).first()
            if not event or (year and event.year_level != year):
                raise common.UploadError('PIT event is not configured for the selected active cohort.')
            teams = filter_teams(teams, stage)
        else:
            from defense.stages.models import DefenseStage
            if not DefenseStage.objects.filter(label=stage, is_active=True).exists():
                raise common.UploadError('Capstone stage is not active.')
        selected = list(teams.select_related('adviser').order_by('pk'))
        if team_ids is not None and {team.pk for team in selected} != set(team_ids):
            raise common.UploadError('Selected teams are unavailable in this term, scope or event roster.')
        workspace = 'instructor' if scope == 'pit' else 'adviser'
        instructors = {}
        if scope == 'pit':
            for assignment in SectionInstructorAssignment.objects.filter(
                    semester=term, is_active=True, faculty__is_active=True,
                    faculty__role__in=['faculty', 'admin']).select_related('faculty'):
                instructors[assignment.faculty_id] = assignment.faculty
        records = []
        for team in selected:
            candidates = list(instructors.values()) if scope == 'pit' else ([team.adviser] if team.adviser_id else [])
            candidates = [user for user in candidates if user.is_active and user.role in ('faculty', 'admin')
                          and (scope == 'pit' or user.is_adviser)
                          and (not reviewers or user.username in reviewers)
                          and workspace_teams_for(user, workspace).filter(pk=team.pk).exists()]
            record = {'team_id': team.pk, 'team_name': team.name, 'project_version': team.project_version,
                      'semester_id': term.pk, 'workspace': workspace, 'reviewer': None, 'problem': ''}
            if len(candidates) == 1:
                record['reviewer'] = {'id': candidates[0].pk, 'username': candidates[0].username}
            elif not candidates:
                record['problem'] = f'No active assigned {workspace} matches this team and the reviewer filter.'
            else:
                names = ', '.join(sorted(user.username for user in candidates))
                record['problem'] = f'Multiple assigned instructors ({names}); choose one with --reviewers USERNAME.'
            records.append(record)
        return term.pk, records


def faculty_token(actor):
    """Mint an ordinary short-lived access token without password/refresh writes."""
    with common.local_read_only():
        from django.contrib.auth import get_user_model
        from rest_framework_simplejwt.tokens import AccessToken
        user = get_user_model().objects.filter(pk=actor['id'], username=actor['username'],
            role__in=['faculty', 'admin'], is_active=True).first()
        if not user:
            raise common.UploadError('The assigned faculty account is no longer active.')
        return str(AccessToken.for_user(user))


class FacultyBatch:
    def __init__(self, base_url):
        self.base_url = common.server_url(base_url)
        self.clients = {}

    def current_record(self, context, original):
        semester, records = discover_reviewers(scope=context['scope'], stage=context['stage'],
            year=context.get('year'), team_ids=[original['team_id']], reviewers=context.get('reviewers'))
        record = records[0]
        if record['problem']:
            raise common.UploadError(record['problem'])
        if semester != context['semester_id'] or any(record[key] != original[key]
                for key in ('semester_id', 'project_version', 'workspace', 'reviewer')):
            raise common.UploadError('The semester, project or assigned reviewer changed. Run a new preview.')
        return record

    def client(self, record):
        actor = record['reviewer']
        identity = (actor['id'], actor['username'])
        if identity not in self.clients:
            client = common.ApiClient(self.base_url)
            client.session.headers.update({'Authorization': f'Bearer {faculty_token(actor)}'})
            self.clients[identity] = client
        return self.clients[identity]

    def params(self, context, record):
        return {'scope': context['scope'], 'stage_label': context['stage'],
                'workspace': record['workspace'], 'team_id': record['team_id']}

    def team(self, context, original):
        record = self.current_record(context, original)
        payload = self.client(record).request('GET', common.API, params=self.params(context, record))
        if (payload.get('active_semester') or {}).get('id') != context['semester_id']:
            raise common.UploadError('Local database and API semesters differ. Check the backend URL.')
        if payload.get('selected_stage') != context['stage'] or payload.get('scope') != context['scope']:
            raise common.UploadError('The API selected a different event/stage or scope.')
        teams = [team for team in payload.get('teams', []) if team.get('id') == record['team_id']]
        if len(teams) != 1:
            raise common.UploadError('Team is unavailable in the assigned faculty workspace.')
        team = teams[0]
        if team.get('semester_id') != record['semester_id'] or team.get('project_version') != record['project_version']:
            raise common.UploadError('The team semester or project changed. Run a new preview.')
        return team

    def endorse(self, context, original, token):
        record = self.current_record(context, original)
        return self.client(record).request('POST', common.API + 'review-endorse/',
            params={**self.params(context, record), 'response_mode': 'team'},
            json={'team_id': record['team_id'], 'stage_label': context['stage'], 'review_token': token})

    def accept_post(self, context, original, target):
        # Post review has no signed snapshot parameter. Refresh and pin the
        # current file ID/revision so a replacement is never silently reviewed.
        actions = post_actions(context, self.team(context, original))
        current = next((action for action in actions if action.get('deliverable_id') == target['deliverable_id']
                        and action.get('file_id') == target.get('file_id')), None)
        if current is None:
            raise common.UploadError('The current post-defense file changed. Run a new preview.')
        if current['status'] == 'skip':
            return None
        if current['status'] != 'ready':
            raise common.UploadError(current['detail'])
        if any(current[key] != target[key] for key in ('definition_fingerprint', 'file_snapshot', 'submission_id')):
            raise common.UploadError('The post-defense requirement or file version changed. Run a new preview.')
        record = self.current_record(context, original)
        fields = {'team_id': record['team_id'], 'stage_label': context['stage'],
                  'deliverable_id': target['deliverable_id'], 'status': 'accepted',
                  'feedback': current.get('feedback', ''), 'clear_defense_revisions': False}
        if target.get('file_id') is not None:
            fields['file_id'] = target['file_id']
        response = self.client(record).request('POST', common.API + 'review/',
            params={**self.params(context, record), 'response_mode': 'team'}, json=fields)
        updated = response.get('team') or {}
        stage = updated.get('selected_stage') or {}
        rows = [row for row in stage.get('post', []) if row.get('id') == target['deliverable_id']]
        files = post_files(rows[0]) if len(rows) == 1 else []
        accepted = any(file.get('id') == target.get('file_id') and file.get('status') == 'accepted' for file in files)
        if updated.get('id') != record['team_id'] or stage.get('stage_label') != context['stage'] or not accepted:
            raise common.UploadError('The response did not confirm file acceptance. Rerun to check server state.')
        return response

    def close(self):
        for client in self.clients.values():
            client.close()


def inspect_team(context, team):
    selected = team.get('selected_stage') or {}
    if selected.get('stage_label') != context['stage']:
        raise common.UploadError('The team payload selected a different event/stage.')
    if selected.get('endorsed') is True and not selected.get('repeat_preparation'):
        return 'skip', 'Already endorsed; existing reviews are preserved.', ''
    if selected.get('endorsement_required') is False:
        return 'skip', 'This event/stage does not require endorsement.', ''
    review = selected.get('endorsement_review') or {}
    if review.get('can_review_and_endorse') is not True:
        raise common.UploadError(review.get('reason') or 'The server does not permit review and endorsement now.')
    token = review.get('review_token')
    if not isinstance(token, str) or not token:
        raise common.UploadError('The API did not provide a current endorsement review token.')
    files = review.get('files') or []
    if any(file.get('status') not in ('pending', 'accepted') for file in files):
        raise common.UploadError('A scheduling file is missing, rejected or awaiting corrections.')
    pending = [file for file in files if file.get('status') != 'accepted']
    if pending and selected.get('can_faculty_review_pre') is not True:
        raise common.UploadError('The server does not permit faculty review of these pre-defense files.')
    labels = ', '.join(file.get('label', file.get('id', 'document')) for file in files)
    return 'ready', f'Accept {len(pending)} pending scheduling requirement(s) and endorse. Files: {labels or "none required"}.', token


def post_files(row):
    submission = row.get('submission') or {}
    files = [file for file in submission.get('files', []) if file.get('is_current', True)]
    if not files and not submission.get('files') and not submission.get('file_history') and submission.get('file_url'):
        # Older primary-file records have no version row. Recheck their actual
        # upload metadata before using the API's ordinary parent review action.
        files = [{**{key: submission.get(key) for key in ('file_name', 'file_url', 'uploaded_at', 'status', 'feedback')},
                  'id': None, 'slot_key': 'primary'}]
    return files


def post_actions(context, team):
    selected = team.get('selected_stage') or {}
    if selected.get('stage_label') != context['stage']:
        raise common.UploadError('The team payload selected a different event/stage.')
    rows = [row for row in selected.get('post', [])
            if row.get('type') == 'post' and row.get('source') != 'defense_minutes']
    if context.get('deliverable'):
        rows = common.selected_requirement(rows, context['deliverable'], team, 'post')
    if not rows:
        return [{'status': 'skip', 'detail': 'No post-defense deliverables are configured.'}]
    actions = []
    for row in rows:
        base = {'deliverable_id': row['id'], 'deliverable_label': row['label']}
        submission = row.get('submission') or {}
        files = post_files(row)
        if row.get('is_waived'):
            actions.append({**base, 'status': 'skip', 'detail': 'This post-defense requirement is waived.'})
            continue
        if not files:
            actions.append({**base, 'status': 'blocked' if row.get('required') else 'skip',
                            'detail': 'Required post-defense file is missing.' if row.get('required') else 'No optional post-defense file uploaded.'})
            continue
        blocker = ''
        if row.get('uploaded') is not True:
            blocker = 'Upload all required documents in this post-defense requirement first.'
        elif submission.get('status') == 'rejected' or any(file.get('status') == 'rejected' for file in files):
            blocker = 'The team must submit the requested post-defense corrections first.'
        elif submission.get('file_replacement_unlocked'):
            blocker = 'A file correction request is still open.'
        if blocker:
            actions.append({**base, 'status': 'blocked', 'detail': blocker})
            continue
        for file in files:
            target = {**base, 'file_id': file.get('id'), 'file_name': file.get('file_name', ''),
                      'submission_id': submission.get('id'),
                      'definition_fingerprint': common.definition_fingerprint(row),
                      'file_snapshot': common.digest({key: file.get(key) for key in (
                          'id', 'slot_key', 'revision', 'file_name', 'file_url', 'uploaded_at',
                          'concept_round_id', 'selected_concept_key')}),
                      'feedback': file.get('feedback') or ''}
            if file.get('status') == 'accepted':
                target.update(status='skip', detail='Already accepted/archived; the existing review is preserved.')
            elif submission.get('files') and (type(file.get('id')) is not int or file['id'] <= 0):
                target.update(status='blocked', detail='The API did not provide a valid current document ID.')
            elif file.get('status') != 'pending' or not file.get('file_url'):
                target.update(status='blocked', detail='No pending uploaded file is available for acceptance.')
            elif row.get('can_faculty_review') is not True or selected.get('can_faculty_review_post') is not True:
                target.update(status='blocked', detail=selected.get('post_unavailable_reason') or
                              'Post-defense review is locked or the defense approval requirements are not met.')
            else:
                target.update(status='ready', detail=f'Accept/archive {file.get("file_name", row["label"])}; no endorsement action.')
            actions.append(target)
    return actions


def write_result(result, record, context, journal):
    result.update(team_id=record['team_id'], team_name=record['team_name'],
                  reviewer=record['reviewer'], workspace=record['workspace'])
    result['context'] = {key: context[key] for key in ('scope', 'stage', 'semester_id')}
    result['context']['timing'] = context.get('timing', 'pre')
    result['time'] = datetime.now(timezone.utc).isoformat()
    actor = (record['reviewer'] or {}).get('username', 'unassigned')
    label = f' / {result["deliverable_id"]}' if result.get('deliverable_id') else ''
    print(f'[{result["status"].upper()}] {record["team_name"]}{label} / {actor}: {result["detail"]}')
    if journal:
        journal.write(json.dumps(result, ensure_ascii=False) + '\n')
        journal.flush()
        os.fsync(journal.fileno())


def run_post_batch(batch, context, records, *, dry_run=False, journal=None):
    results = []
    stop = False
    for record in records:
        try:
            if record['problem']:
                raise common.UploadError(record['problem'])
            actions = post_actions(context, batch.team(context, record))
        except (common.UploadError, OSError) as error:
            actions = [{'status': 'blocked', 'detail': str(error)}]
            stop = isinstance(error, common.ApiError) and error.status in (401, 429)
        for action in actions:
            result = {key: action[key] for key in ('deliverable_id', 'deliverable_label', 'file_id', 'file_name', 'status', 'detail') if key in action}
            try:
                if action['status'] == 'ready' and not dry_run:
                    response = batch.accept_post(context, record, action)
                    if response is None:
                        result.update(status='skip', detail='File became accepted or waived; existing state is preserved.')
                    else:
                        result.update(status='archived', detail=f'Accepted/archived {action["file_name"]} through the faculty review API.')
            except (common.UploadError, OSError) as error:
                result.update(status='blocked', detail=str(error))
                stop = isinstance(error, common.ApiError) and error.status in (401, 429)
            write_result(result, record, context, journal)
            results.append(result)
            if stop:
                break
        if stop:
            print('Stopping after authentication/rate-limit failure; remaining files were not processed.')
            break
    print('Summary: ' + json.dumps(dict(Counter(row['status'] for row in results))))
    return 2 if any(row['status'] == 'blocked' for row in results) else 0


def run_batch(batch, context, records, *, dry_run=False, journal=None):
    if context.get('timing') == 'post':
        return run_post_batch(batch, context, records, dry_run=dry_run, journal=journal)
    results = []
    for record in records:
        result = {'team_id': record['team_id'], 'team_name': record['team_name'],
                  'reviewer': record['reviewer'], 'workspace': record['workspace']}
        stop = False
        try:
            if record['problem']:
                raise common.UploadError(record['problem'])
            status, detail, token = inspect_team(context, batch.team(context, record))
            result.update(status=status, detail=detail)
            if status == 'ready' and not dry_run:
                response = batch.endorse(context, record, token)
                updated = response.get('team') or {}
                stage = updated.get('selected_stage') or {}
                if updated.get('id') != record['team_id'] or stage.get('stage_label') != context['stage'] or stage.get('endorsed') is not True:
                    raise common.UploadError('The response did not confirm endorsement. Rerun to check server state.')
                result.update(status='endorsed', detail='Scheduling files reviewed and team endorsed by the assigned faculty.')
        except (common.UploadError, OSError) as error:
            result.update(status='blocked', detail=str(error))
            stop = isinstance(error, common.ApiError) and error.status in (401, 429)
        write_result(result, record, context, journal)
        results.append(result)
        if stop:
            print(f'Stopping after authentication/rate-limit failure; {len(records) - len(results)} teams unprocessed.')
            break
    print('Summary: ' + json.dumps(dict(Counter(row['status'] for row in results))))
    return 2 if any(row['status'] == 'blocked' for row in results) else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    targets = parser.add_mutually_exclusive_group(required=True)
    targets.add_argument('--all-teams', action='store_true', help='Process the whole selected active cohort.')
    targets.add_argument('--team-id', type=int, nargs='+', help='Process only these team IDs.')
    parser.add_argument('--scope', choices=['pit', 'capstone'], default='pit')
    parser.add_argument('--year', type=common.year_label, help='Year number, e.g. --year 1.')
    parser.add_argument('--stage', help='Event/stage; selected automatically only when exactly one is available.')
    parser.add_argument('--timing', choices=['pre', 'post'], default='pre',
                        help='pre: review and endorse (default); post: accept/archive files only.')
    parser.add_argument('--deliverable', help='With --timing post, select one post requirement by ID or label.')
    parser.add_argument('--reviewers', nargs='+', help='Use only these assigned faculty usernames; resolves multiple instructors.')
    parser.add_argument('--base-url', default='http://127.0.0.1:8000')
    parser.add_argument('--dry-run', action='store_true', help='Preview only. Without this flag, save the selected reviews/actions.')
    args = parser.parse_args(argv)
    batch = None
    try:
        if args.deliverable and args.timing != 'post':
            raise common.UploadError('--deliverable requires --timing post; pre mode reviews all scheduling requirements together.')
        stage = common.batch_stage(args.scope, args.year, args.stage)
        semester, records = discover_reviewers(scope=args.scope, stage=stage, year=args.year,
            team_ids=args.team_id, reviewers=args.reviewers)
        if not records:
            raise common.UploadError('No teams match the selected active cohort.')
        context = {'scope': args.scope, 'stage': stage, 'year': args.year,
                   'semester_id': semester, 'reviewers': args.reviewers,
                   'timing': args.timing, 'deliverable': args.deliverable}
        action = 'REVIEW & ENDORSE' if args.timing == 'pre' else 'ACCEPT & ARCHIVE POST FILES'
        print(f'Mode: {"DRY RUN (no reviews or endorsements saved)" if args.dry_run else "LIVE"} / {action}')
        print(f'{args.scope.upper()} / {stage} / {len(records)} teams / assigned {"instructors" if args.scope == "pit" else "advisers"}')
        batch = FacultyBatch(args.base_url)
        log_root = common.ROOT / '.tmp'
        log_root.mkdir(parents=True, exist_ok=True)
        log_key = common.digest({'server': batch.base_url, **context, 'teams': [r['team_id'] for r in records]})[:16]
        journal_path = log_root / f'review-endorse-{log_key}.jsonl'
        if args.dry_run:
            with journal_path.open('a', encoding='utf-8') as journal:
                return run_batch(batch, context, records, dry_run=True, journal=journal)
        with common.apply_lock(log_root / f'review-endorse-{log_key}.json'), journal_path.open('a', encoding='utf-8') as journal:
            return run_batch(batch, context, records, journal=journal)
    except (common.UploadError, OSError, ValueError, TypeError, KeyError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('Stopped. Rerun to check server state before trying again.', file=sys.stderr)
        return 130
    finally:
        if batch:
            batch.close()


if __name__ == '__main__':
    raise SystemExit(main())
