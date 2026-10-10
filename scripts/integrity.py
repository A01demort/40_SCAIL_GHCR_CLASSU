"""Seal/check tracked source bytes and the installed package inventory."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory():
    return dict(sorted((re.sub(r'[-_.]+', '-', d.metadata['Name']).lower(), d.version)
                       for d in importlib.metadata.distributions()))


def source_files(root, manifest):
    result = {}
    for repo in manifest['repositories']:
        directory = root / repo['path']
        commit = subprocess.check_output(['git', '-C', str(directory), 'rev-parse', 'HEAD'], text=True).strip()
        if commit != repo['commit']:
            raise RuntimeError(f"Commit drift: {repo['name']}")
        files = subprocess.check_output(['git', '-C', str(directory), 'ls-files', '-z']).decode().split('\0')
        for name in filter(None, files):
            if repo['path'] == '.' and Path(name).parts[0] in {'models', 'input', 'output', 'temp', 'user'}:
                continue
            file = directory / name
            result[file.relative_to(root).as_posix()] = sha(file)
        # Ignore runtime caches and user configuration, but never new executable code.
        untracked = subprocess.check_output(['git', '-C', str(directory), 'ls-files', '--others', '--exclude-standard', '-z']).decode().split('\0')
        for name in filter(None, untracked):
            if Path(name).suffix in {'.py', '.js', '.sh', '.pth'}:
                raise RuntimeError(f'Untracked executable source: {directory / name}')
    expected = {Path(r['path']).name for r in manifest['repositories'] if r['path'] != '.'}
    actual = {p.name for p in (root / 'custom_nodes').iterdir() if p.is_dir() and p.name != '__pycache__'}
    if expected != actual:
        raise RuntimeError(f'Custom node directory drift: {sorted(expected ^ actual)}')
    # gitignore must not conceal an extra custom node or Python startup hook.
    code_suffixes = {'.py', '.js', '.sh', '.pth', '.css', '.html'}
    for file in root.rglob('*'):
        relative = file.relative_to(root)
        if '.git' in relative.parts or relative.parts[0] in {'models', 'input', 'output', 'temp', 'user'}:
            continue
        if file.is_file() and file.suffix in code_suffixes and relative.as_posix() not in result:
            raise RuntimeError(f'Unexpected executable source: {relative}')
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['seal', 'check'])
    p.add_argument('--root', type=Path, default=Path('/opt/ComfyUI'))
    p.add_argument('--config', type=Path, default=Path('/opt/scail'))
    a = p.parse_args()
    manifest = json.loads((a.config / 'locks/sources.json').read_text())
    current = {'packages': inventory(), 'sources': source_files(a.root, manifest)}
    seal = a.config / 'locks/installed.json'
    if a.mode == 'seal':
        seal.write_text(json.dumps(current, indent=2) + '\n')
    elif current != json.loads(seal.read_text()):
        raise SystemExit('Runtime drift detected. Redeploy the approved image digest; do not pip install in this Pod.')
    subprocess.run(['python', '-m', 'pip', 'check'], check=True)


if __name__ == '__main__':
    main()
