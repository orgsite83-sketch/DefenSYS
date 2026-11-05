# Repository delivery and reader library

The reader library uses topics, one card per project, and sections from actual
submitted deliverables. Labels are captured metadata; file extensions do not
establish deliverable associations. Legacy unassigned files use Other materials.
Controls use installed shadcn components, neutral text, Inter, and DefenSYS
surfaces. No record relabeling or schema migration is required.

## Loading boundaries

- `/api/repository/archive/catalog/` returns 24 project summaries by default,
  at most 60, with server filters, ordering, facets, and pagination. Offset is
  limited to 5,000; narrow filters for larger collections.
- `/api/repository/archive/project/?project_key=...` loads one project's metadata
  on demand. The UI renders 20 files per selected deliverable before Load more.
  The endpoint currently returns all metadata for that individual project.
- Full extracted text never travels in these responses. Cold reads process one
  project at a time; warm reads reuse a one-hour metadata/taxonomy cache keyed to
  current records, text hashes, and definitions. Every request still queries
  visibility. PostgreSQL computes text hashes without sending text to Python on
  warm reads. Cache keys are isolated by the backend secret.
- Full-text search retains its existing implementation. Existing PDF viewing is
  retained and still uses authenticated bytes, with a two-minute read timeout.
  Progressive PDF and transcoding are separate follow-ups.

## First rollout: usertest only

Deploy the matching backend and prepared web release together to the isolated
usertest checkout. Preserve `.env`, `settings_online_usertest.py`, media, and
recovery data. Production and clienttest do not need configuration changes.
Use the existing release preparation/publishing tools with a newer build number;
a raw `flutter build web` output is only a verification artifact.

Set only in `~/defensys-environments/usertest/backend/.env`:

```dotenv
DEFENSYS_MEDIA_SESSIONS=True
```

Confirm its existing `REDIS_URL` works, then restart only the active usertest
backend units. A Redis media cache is configured automatically with DEBUG=False;
`DEFENSYS_MEDIA_REDIS_URL` can explicitly select its URL. Django now supports
bounded single byte ranges for protected playback without Nginx offload.

The browser grant is opaque, HttpOnly, host-only, SameSite=Strict, scoped to
`/api/media/`, and valid for at most ten minutes or the access token's remaining
lifetime. Every file request repeats the account/guest invitation and media
permission checks. Cookies cannot renew themselves or authenticate other APIs.
Logout explicitly revokes the grant through the media endpoint.

## Optional Nginx offload

The existing test media is in a private home directory. Preserve its ACLs first.
Inspect the resolved paths and reject symlink escapes. Grant `www-data` execute
only on the parent home/environment/usertest/backend directories, and read and
traverse only within usertest's media directory. Add default read/traverse ACLs
to media directories for subsequent uploads. Use `getfacl`/`setfacl`; never make
the checkout or its `.env` publicly readable. The server needs the `acl` package.
The configuration helper checks access but does not alter ACLs or install it.

Run the updated `execution/configure_testing_nginx.py` as the normal defensys SSH
user after `sudo -v`:

```sh
/opt/defensys/backend/venv/bin/python \
  ~/defensys-transfer/configure_testing_nginx.py \
  --phase https --usertest-protected-media
```

Review the dry run, then repeat with `--apply`. The helper accepts the previous
managed config, snapshots it, validates Nginx, reloads, and rolls back on failure.
It adds only a usertest internal alias at `/_protected_usertest_media/`, with
symlinks disabled and single ranges. Public media URLs still proxy authorization
through Django. External requests to the internal location must return 404.

After the internal location is loaded, set this in the isolated usertest `.env`
and restart only usertest:

```dotenv
DEFENSYS_MEDIA_X_ACCEL_PREFIX=/_protected_usertest_media
```

Check authorized playback and seeking (200/206, correct range/length), then
unauthorized/revoked access and direct internal URLs. Measure cold/warm catalog
time, bytes, HTTP worker memory, and `memory.events` on the restored dataset.
Live throughput and codec compatibility have not been established by local tests.
Do not increase service memory limits without measurements.

Rollback: clear the X-Accel prefix before removing the internal route. Disable
media sessions to restore byte-based playback. Re-run managed HTTPS configuration
without `--usertest-protected-media`, restore ACLs if necessary, and restore the
previous matching frontend/backend release. A database restore is unnecessary.

## Local verification notes

Repository, authentication, viewer-format, responsive-theme, catalog-cache,
range/permission, guest-revocation, and managed Nginx configuration checks pass.
The complete frontend analyzer also reports an existing unrelated override error
in `test/widgets/stage_access_management_test.dart` (missing
`openCurrentSemester` on its fake archive notifier), alongside existing warnings.
Use focused analysis for this change; do not describe the entire repository's
analyzer as clean.

On Windows, pass an absolute `--output` path to the Flutter release build. A
relative parent-directory output caused the shader compiler to fail writing its
output; the absolute path resolves that failure. Standard JavaScript web builds
are used; existing dependency Wasm compatibility warnings are separate.
