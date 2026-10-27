"""Save a scoped set of shared-module titles through each actual leader's API.

Read-only preflight is the default. Use --apply to save, then verify with GET.
Reuse the existing trusted local student authentication without credential edits.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from upload_deliverables import (
    ApiClient, UploadError, local_read_only, student_access_token,
)

API = '/api/repository/deliverables/concepts/'


def discover(manifest):
    with local_read_only():
        from academic_period_management.models import Semester
        from student_teams.models import StudentTeam

        terms = list(Semester.objects.filter(is_active=True))
        if len(terms) != 1:
            raise UploadError('Exactly one active semester is required.')
        records = []
        for name, title in manifest['titles'].items():
            if not isinstance(title, str) or not title.strip() or len(title) > 255:
                raise UploadError(f'Invalid module title for {name}.')
            matches = list(StudentTeam.objects.filter(
                semester=terms[0], year_level=manifest['year_level'],
                section=manifest['section'], name=name,
            ).select_related('leader'))
            if len(matches) != 1:
                raise UploadError(f'Expected exactly one current team named {name}.')
            team = matches[0]
            leader = team.leader
            if (not leader or not leader.is_active or leader.role != 'student'
                    or not team.memberships.filter(student_id=leader.pk).exists()):
                raise UploadError(f'{name} has no active student leader in its roster.')
            records.append({'team_id': team.pk, 'name': name, 'leader_id': leader.pk,
                            'username': leader.username, 'title': title.strip()})
        return records


def load(client, manifest, record):
    payload = client.request('GET', API, params={
        'team_id': record['team_id'], 'stage_label': manifest['stage_label'],
        'response_mode': 'concept_titles',
    })
    if payload.get('team_id') != record['team_id'] or payload.get('stage_label') != manifest['stage_label']:
        raise UploadError('API returned a different team or stage.')
    workflow = payload['concept_workflow']
    if workflow.get('selection_mode') != 'shared_module':
        raise UploadError(f'{record["name"]} is not in a shared-module workflow.')
    rows = workflow['concepts']
    matches = [c for c in rows if c['key'] == manifest['concept_key']]
    if len(matches) != 1 or matches[0].get('system_title') != manifest['system_title']:
        raise UploadError(f'{record["name"]} is linked to a different shared system.')
    return workflow, matches[0]


def status(workflow, item, record):
    state = (item.get('title_review') or {}).get('state')
    if (workflow.get('round_id') is not None and item['title'] == record['title']
            and state in ('submitted', 'accepted')):
        return 'already_saved'
    if not workflow.get('can_edit_titles'):
        raise UploadError(f'{record["name"]}: leader cannot edit this title.')
    if item.get('faculty_confirmed'):
        raise UploadError(f'{record["name"]}: confirmed title requires faculty review.')
    if workflow.get('title_workflow_version') != 1:
        raise UploadError('This tool uses the legacy title editor save action only.')
    if state not in ('draft', 'changes_requested'):
        raise UploadError(f'{record["name"]}: current title is not an editable draft.')
    return 'ready'


def run(manifest, *, base_url, apply, report):
    records = discover(manifest)
    clients = []
    results = []
    try:
        # Preflight every target before making the first write.
        prepared = []
        for record in records:
            client = ApiClient(base_url)
            client.session.trust_env = False
            clients.append(client)
            client.session.headers['Authorization'] = 'Bearer ' + student_access_token(record)
            workflow, item = load(client, manifest, record)
            prepared.append((client, record, workflow, status(workflow, item, record)))
        for client, record, before, initial_status in prepared:
            result = {**record, 'status': initial_status}
            if apply and initial_status == 'ready':
                if record not in discover(manifest):
                    raise UploadError('Team, term or leader changed after preflight.')
                current, item = load(client, manifest, record)
                if current != before:
                    raise UploadError('Proposal changed after preflight; rerun to review it.')
                titles = [{'key': c['key'], 'title': record['title']
                           if c['key'] == manifest['concept_key'] else c['title']}
                          for c in current['concepts']]
                client.request('POST', API, params={'response_mode': 'concept_titles'}, json={
                    'team_id': record['team_id'], 'stage_label': manifest['stage_label'],
                    'action': 'save_draft_titles', 'concepts': titles,
                    'review_token': current['module_review_token'],
                })
                result['status'] = 'saved'
            if apply:
                after, item = load(client, manifest, record)
                if after.get('round_id') is None or item['title'] != record['title']:
                    raise UploadError(f'{record["name"]}: saved title verification failed.')
                # Preserve titles and confirmation state in the other concept slots.
                other_before = [c for c in before['concepts'] if c['key'] != manifest['concept_key']]
                other_after = [c for c in after['concepts'] if c['key'] != manifest['concept_key']]
                if [(c['key'], c['title'], c.get('faculty_confirmed')) for c in other_before] != [
                        (c['key'], c['title'], c.get('faculty_confirmed')) for c in other_after]:
                    raise UploadError(f'{record["name"]}: another concept changed.')
                result.update(verified=True, round_id=after['round_id'],
                              title_state=item['title_review']['state'])
            results.append(result)
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps(results, indent=2), encoding='utf-8')
            print(json.dumps(result), flush=True)
        return results
    finally:
        for client in clients:
            client.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--base-url', default='http://127.0.0.1:8000')
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        run(json.loads(args.manifest.read_text(encoding='utf-8')),
            base_url=args.base_url, apply=args.apply, report=args.report)
    except UploadError as error:
        parser.exit(1, f'{error}\n')
