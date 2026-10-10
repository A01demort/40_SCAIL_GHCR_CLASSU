"""Fetch only the source commits in the reviewed manifest (image build only)."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    manifest, destination = Path(sys.argv[1]), Path(sys.argv[2])
    for repo in json.loads(manifest.read_text())['repositories']:
        path = destination / repo['path']
        if (path / '.git').exists():
            raise SystemExit(f'Refusing to reuse source checkout: {path}')
        path.mkdir(parents=True, exist_ok=True)
        run('git', 'init', str(path))
        run('git', '-C', str(path), 'remote', 'add', 'origin', repo['url'])
        run('git', '-C', str(path), 'fetch', '--depth=1', 'origin', repo['commit'])
        run('git', '-C', str(path), 'checkout', '--detach', 'FETCH_HEAD')
        if run('git', '-C', str(path), 'rev-parse', 'HEAD') != repo['commit']:
            raise SystemExit(f'Wrong commit: {path}')
        requirements_file = repo.get('requirements_file', 'requirements.txt')
        requirements = (path / requirements_file).read_bytes() if requirements_file else b''
        actual = hashlib.sha256(requirements).hexdigest()
        if actual != repo['requirements_sha256']:
            raise SystemExit(f'Requirements changed: {path}')
        print(f"Locked {repo['name']}: {repo['commit']}", flush=True)


if __name__ == '__main__':
    main()
