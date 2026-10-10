"""Keep the solver input tied to the exact upstream requirement snapshots."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def render(root=ROOT):
    manifest = json.loads((root / 'locks/sources.json').read_text())
    packages = json.loads((root / 'locks/source-packages.json').read_text())['packages']
    replacements = {p['repository'].removesuffix('.git'): f"{p['name']} @ {p['url']}#sha256={p['sha256']}" for p in packages}
    lines = ['# Generated from all original custom-node requirements; see scripts/lock.sh.',
             '# VCS dependencies use reviewed commit archives and SHA256 hashes.']
    for repo in manifest['repositories']:
        raw = (root / 'requirements/upstream' / (repo['name'] + '.txt')).read_bytes()
        if hashlib.sha256(raw).hexdigest() != repo['requirements_sha256']:
            raise RuntimeError(f"Upstream requirements hash mismatch: {repo['name']}")
        lines += ['', f"# {repo['name']} @ {repo['commit']}"]
        for line in raw.decode('utf-8-sig').splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line.startswith('git+'):
                key = line.removeprefix('git+').removesuffix('.git')
                if key not in replacements:
                    raise RuntimeError(f'Unpinned VCS requirement: {line}')
                line = replacements[key]
            lines.append(line)
    return '\n'.join(lines + ['', '-r pins.txt']) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    path = ROOT / 'requirements/requirements.in'
    expected = render()
    if args.write:
        path.write_text(expected, encoding='utf-8', newline='\n')
    elif path.read_text(encoding='utf-8') != expected:
        raise SystemExit('Stale requirements.in; run scripts/requirements_input.py --write in maintenance checkout.')


if __name__ == '__main__':
    main()
