"""Check node registration and server startup errors."""
import argparse
import json
from pathlib import Path
import re
import time
import urllib.request

ERRORS = re.compile(r'IMPORT FAILED|Cannot import .*module for custom nodes|Traceback \(most recent call last\)|Error importing dependencies|ERROR \*|Failed to initialize database|comfyui-embedded-docs package not found')


def check(contract, info, extensions, log, manifest=None):
    failures = []
    for kind in contract['required_node_types']:
        if kind not in info:
            failures.append(f"Missing node type: {kind}")
    for fragment in contract['required_frontend_extensions']:
        if not any(fragment in url for url in extensions):
            failures.append(f'Missing frontend extension: {fragment}')
    if manifest is not None:
        loaded = set()
        for line in log.splitlines():
            match = re.search(r'\d+(?:\.\d+)? seconds: (.+)', line)
            if match:
                loaded.add(match.group(1).strip().replace('\\', '/').rstrip('/').rsplit('/', 1)[-1])
        for repo in manifest['repositories']:
            if repo['path'] != '.' and repo['path'].rsplit('/', 1)[-1] not in loaded:
                failures.append(f"No successful import recorded for original pack: {repo['name']}")
    failures += [line for line in log.splitlines() if ERRORS.search(line)]
    return failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:8188')
    parser.add_argument('--contract', type=Path, default=Path('/opt/scail/requirements/node-types.json'))
    parser.add_argument('--sources', type=Path, default=Path('/opt/scail/locks/sources.json'))
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout
    last_error = 'not started'
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(args.url + '/object_info', timeout=10) as response:
                info = json.load(response)
            with urllib.request.urlopen(args.url + '/extensions', timeout=10) as response:
                extensions = json.load(response)
            break
        except (OSError, ValueError) as error:
            last_error = str(error)
            time.sleep(1)
    else:
        raise SystemExit(f'ComfyUI readiness timeout: {last_error}')
    failures = check(json.loads(args.contract.read_text(encoding='utf-8')), info, extensions,
                     args.log.read_text(encoding='utf-8', errors='replace'),
                     json.loads(args.sources.read_text(encoding='utf-8')))
    if failures:
        raise SystemExit('\n'.join(failures))
    print('Node registration and startup log checks passed.')


if __name__ == '__main__':
    main()
