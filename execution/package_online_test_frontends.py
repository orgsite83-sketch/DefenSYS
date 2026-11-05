"""Package two prepared origin-specific web releases for isolated server delivery."""
import argparse
import json
from pathlib import Path
import shutil
import tarfile
import tempfile

from prepare_app_release import sha256, verify_web

ROOT = Path(__file__).resolve().parents[1]
ORIGINS = {'usertest': 'https://test.defensys.site',
           'clienttest': 'https://client-test.defensys.site'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--usertest', type=Path, required=True, help='Prepared release directory.')
    parser.add_argument('--clienttest', type=Path, required=True, help='Prepared release directory.')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('Output exists; refusing to overwrite it.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='test-frontends-', dir=output.parent) as temp:
        delivery = Path(temp)
        artifacts = delivery / 'artifacts'
        artifacts.mkdir()
        record = {'releases': {}, 'checksums': {}}
        for environment, origin in ORIGINS.items():
            release_dir = getattr(args, environment).resolve()
            verify_web(release_dir / 'artifact')
            if origin.encode() not in (release_dir / 'artifact/main.dart.js').read_bytes():
                parser.error('Compiled release origin mismatch: ' + environment)
            prepared = json.loads((release_dir / 'deployment.json').read_text())
            archive = release_dir / Path(prepared['archive']).name
            if sha256(archive) != prepared['sha256']:
                parser.error('Prepared release checksum mismatch: ' + environment)
            shutil.copyfile(archive, artifacts / archive.name)
            record['releases'][environment] = {'origin': origin, 'archive': archive.name,
                'sha256': prepared['sha256'], 'release_id': prepared['release_id']}
        for name in ('execution/prepare_app_release.py', 'execution/publish_app_release.py',
                     'execution/verify_web_release.py', 'deployment/web/retire_flutter_service_worker.js'):
            destination = delivery / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        record['checksums'] = {path.relative_to(delivery).as_posix(): sha256(path)
                               for path in delivery.rglob('*') if path.is_file()}
        (delivery / 'delivery.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
        with tarfile.open(output, 'w:gz') as archive:
            for path in sorted(delivery.rglob('*')):
                if path.is_file():
                    archive.add(path, arcname=path.relative_to(delivery).as_posix(), recursive=False)
    print(json.dumps({'bundle': str(output), 'sha256': sha256(output),
                      'bytes': output.stat().st_size, 'releases': record['releases']}, indent=2))


if __name__ == '__main__':
    main()
