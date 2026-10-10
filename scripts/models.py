"""Explicit model provisioning: pinned URLs, size and SHA256; atomic downloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import urllib.request


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def valid(path, model):
    return path.is_file() and path.stat().st_size == model['size'] and digest(path) == model['sha256']


def target_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'Invalid model path: {relative}')
    return path


def provision(models, root, download=False):
    failures = []
    for model in models:
        path = target_path(root, model['path'])
        if valid(path, model):
            print(f"VERIFIED {model['path']}", flush=True)
            continue
        if not download:
            failures.append(f"Missing or corrupt model: {model['path']}")
            continue
        # Never silently replace a user's existing mismatched model.
        if path.exists():
            failures.append(f'Model differs from lock; move it aside before retrying: {path}')
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_name(path.name + '.scail-part')
        headers = {}
        if model['url'].startswith('https://huggingface.co/') and os.environ.get('HF_TOKEN'):
            headers['Authorization'] = 'Bearer ' + os.environ['HF_TOKEN']
        print(f"DOWNLOADING {model['path']} ({model['size']} bytes)", flush=True)
        with urllib.request.urlopen(urllib.request.Request(model['url'], headers=headers), timeout=120) as source:
            with partial.open('wb') as dest:
                for block in iter(lambda: source.read(8 * 1024 * 1024), b''):
                    dest.write(block)
        if not valid(partial, model):
            raise RuntimeError(f'Incomplete or changed download: {partial}')
        partial.replace(path)
        print(f"VERIFIED {model['path']}", flush=True)
    return failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['download', 'check'])
    parser.add_argument('--root', type=Path, default=Path('/workspace/ComfyUI/models'))
    parser.add_argument('--lock', type=Path, default=Path('/opt/scail/locks/models.json'))
    args = parser.parse_args()
    failures = provision(json.loads(args.lock.read_text())['models'], args.root, args.mode == 'download')
    if failures:
        raise SystemExit('\n'.join(failures))
    print('All locked model bytes verified.')


if __name__ == '__main__':
    main()
