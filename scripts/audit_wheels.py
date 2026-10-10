"""Audit Linux artifacts and split hash-locked binary/source installation inputs."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request
from packaging.requirements import Requirement
from packaging.tags import cpython_tags, compatible_tags
from packaging.utils import parse_wheel_filename

ROOT = Path(__file__).resolve().parents[1]
# These upstream packages publish only source archives at the selected versions.
SOURCE_ONLY = {'antlr4-python3-runtime', 'basicsr', 'fairscale', 'filterpy',
               'fvcore', 'insightface', 'iopath', 'sageattention', 'pixeloe', 'pycairo', 'wget'}


def records(text):
    blocks = re.split(r'(?m)(?=^[a-z0-9][a-z0-9._-]*(?:==| @ ))', text)
    result = []
    for block in blocks:
        if not re.match(r'^[a-z0-9][a-z0-9._-]*(?:==| @ )', block):
            continue
        requirement = Requirement(block.splitlines()[0].rstrip(' \\'))
        hashes = set(re.findall(r'--hash=sha256:([a-f0-9]{64})', block))
        if requirement.url:
            hashes.update(urllib.parse.parse_qs(urllib.parse.urlparse(requirement.url).fragment).get('sha256', []))
        if not hashes:
            raise RuntimeError(f'Unhashed package: {requirement.name}')
        result.append((requirement, hashes, block))
    return result


def main():
    platforms = [f'manylinux_2_{minor}_x86_64' for minor in range(31, 4, -1)]
    platforms += ['manylinux2014_x86_64', 'manylinux2010_x86_64', 'manylinux1_x86_64', 'linux_x86_64']
    tags = set(cpython_tags((3, 10), ['cp310'], platforms))
    tags.update(compatible_tags((3, 10), 'cp310', platforms))
    source_packages = {p['name']: p for p in json.loads((ROOT / 'locks/source-packages.json').read_text())['packages']}
    text = (ROOT / 'locks/requirements-linux-cu124.lock').read_text()
    entries = records(text)

    def audit(entry):
        requirement, hashes, _ = entry
        name = requirement.name
        if requirement.url:
            url = requirement.url.split('#')[0]
            filename = urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit('/', 1)[-1])
            if filename.endswith('.whl'):
                _, version, _, wheel_tags = parse_wheel_filename(filename)
                if not tags.intersection(wheel_tags):
                    raise RuntimeError(f'Wrong target wheel: {filename}')
                with urllib.request.urlopen(f'https://download.pytorch.org/whl/cu124/{name}/', timeout=60) as response:
                    page = response.read().decode()
                verified = False
                for link in re.findall(r'href="([^"]+)"', page):
                    parts = urllib.parse.urlparse(link)
                    digest = urllib.parse.parse_qs(parts.fragment).get('sha256', [''])[0]
                    if urllib.parse.unquote(parts.path).endswith('/' + filename) and digest in hashes:
                        verified = True
                        break
                if not verified:
                    raise RuntimeError(f'Official wheel hash mismatch: {name}')
                return {'package': name, 'version': str(version), 'kind': 'wheel', 'artifact': filename, 'sha256': digest}
            pinned = source_packages[name]
            if url != pinned['url'] or pinned['sha256'] not in hashes:
                raise RuntimeError(f'Unreviewed source URL: {name}')
            digest = hashlib.sha256()
            with urllib.request.urlopen(url, timeout=60) as response:
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
            if digest.hexdigest() != pinned['sha256']:
                raise RuntimeError(f'Changed archive: {name}')
            return {'package': name, 'kind': 'source', 'artifact': url, 'sha256': digest.hexdigest()}
        versions = list(requirement.specifier)
        if len(versions) != 1 or versions[0].operator != '==':
            raise RuntimeError(f'Unpinned package: {requirement}')
        version = versions[0].version
        with urllib.request.urlopen(f'https://pypi.org/pypi/{name}/{version}/json', timeout=60) as response:
            data = json.load(response)
        artifacts = [f for f in data['urls'] if not f['yanked'] and f['digests']['sha256'] in hashes]
        for artifact in artifacts:
            if artifact['filename'].endswith('.whl'):
                _, _, _, wheel_tags = parse_wheel_filename(artifact['filename'])
                if tags.intersection(wheel_tags):
                    return {'package': name, 'version': version, 'kind': 'wheel', 'artifact': artifact['filename'], 'sha256': artifact['digests']['sha256']}
        for artifact in artifacts:
            if name in SOURCE_ONLY and artifact['packagetype'] == 'sdist':
                return {'package': name, 'version': version, 'kind': 'source', 'artifact': artifact['filename'], 'sha256': artifact['digests']['sha256']}
        raise RuntimeError(f'No compatible Linux wheel or approved source build: {name}=={version}')

    def checked(entry):
        try:
            return audit(entry)
        except Exception as error:
            return {'error': str(error), 'package': entry[0].name}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(checked, entries))
    failures = [result for result in results if 'error' in result]
    if failures:
        raise SystemExit(json.dumps(failures, indent=2))
    outputs = {'binary': [], 'source': [], 'shared-modules': []}
    for entry, result in zip(entries, results):
        kind = 'binary' if result['kind'] == 'wheel' else 'source'
        outputs[kind].append(entry[2])
        if result['package'] in {'opencv-contrib-python', 'onnxruntime-gpu'}:
            outputs['shared-modules'].append(entry[2])
    for kind, blocks in outputs.items():
        (ROOT / 'locks' / (kind + '.lock')).write_text(''.join(blocks), encoding='utf-8', newline='\n')
    output = ROOT / 'test-results'
    output.mkdir(exist_ok=True)
    report = {'target': 'CPython 3.10 Linux x86_64 glibc 2.31',
              'requirements_sha256': hashlib.sha256(text.encode()).hexdigest(), 'artifacts': results}
    (output / 'wheel-audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"PASS: {len(outputs['binary'])} compatible wheels and {len(outputs['source'])} pinned source builds. Native sources compile during RunPod setup.")


if __name__ == '__main__':
    main()
