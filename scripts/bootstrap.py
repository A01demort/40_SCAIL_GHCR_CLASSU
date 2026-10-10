"""Install a hash-locked environment on the mounted volume and reuse it on restart."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile


def fingerprint(config):
    digest = hashlib.sha256()
    digest.update(f'bootstrap-v1:{sys.version_info[:3]}:{sys.platform}:{platform.machine()}'.encode())
    for directory in ['locks', 'requirements', 'scripts']:
        for path in sorted((config / directory).rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            digest.update(path.relative_to(config).as_posix().encode() + b'\0' + path.read_bytes())
    return digest.hexdigest()


def install_commands(config, target, python):
    pip = [str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '--no-cache-dir',
           '--no-deps', '--require-hashes', '--index-url', 'https://pypi.org/simple']
    return [
        [sys.executable, str(config / 'scripts/requirements_input.py')],
        [sys.executable, str(config / 'scripts/sources.py'), str(config / 'locks/sources.json'), str(target / 'ComfyUI')],
        [sys.executable, '-m', 'venv', str(target / 'venv')],
        pip + ['--only-binary=:all:', '-r', str(config / 'locks/binary.lock')],
        pip + ['--no-binary=:all:', '--no-build-isolation', '--use-pep517', '-r', str(config / 'locks/source.lock')],
        pip + ['--force-reinstall', '--only-binary=:all:', '-r', str(config / 'locks/shared-modules.lock')],
        [str(python), '-m', 'pip', 'check'],
    ]


def install(config, target, workspace):
    python = target / 'venv/bin/python'
    env = {key: value for key, value in os.environ.items() if not key.startswith(('PIP_', 'UV_')) and key != 'PYTHONHOME'}
    env.update({'PIP_CONFIG_FILE': os.devnull, 'PYTHONNOUSERSITE': '1', 'PYTHONPATH': '',
                'SAM2_BUILD_CUDA': '0', 'MAX_JOBS': '2', 'VIRTUAL_ENV': str(target / 'venv'),
                'PATH': str(target / 'venv/bin') + os.pathsep + os.environ.get('PATH', '')})
    for command in install_commands(config, target, python):
        subprocess.run(command, check=True, env=env)
    shared = workspace / 'ComfyUI/models'
    shared.mkdir(parents=True, exist_ok=True)
    defaults = target / 'ComfyUI/models'
    for source in defaults.rglob('*'):
        destination = shared / source.relative_to(defaults)
        if source.is_file() and not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
    shutil.rmtree(defaults)
    defaults.symlink_to(shared, target_is_directory=True)
    subprocess.run([str(python), str(config / 'scripts/integrity.py'), 'seal',
                    '--root', str(target / 'ComfyUI'), '--config', str(config),
                    '--seal', str(target / 'installed.json')], check=True, env=env)


def ensure(config, state, workspace, installer=install):
    key = fingerprint(config)
    environments = state / 'environments'
    environments.mkdir(parents=True, exist_ok=True)
    records = state / 'releases'
    records.mkdir(exist_ok=True)
    record = records / (key + '.json')
    if record.exists():
        data = json.loads(record.read_text(encoding='utf-8'))
        target = (environments / data['environment']).resolve()
        if target.parent != environments.resolve() or data['fingerprint'] != key:
            raise RuntimeError('Invalid environment record')
        if not (target / 'installed.json').is_file() or not (target / 'venv/bin/python').is_file():
            raise RuntimeError('Incomplete saved environment; installation record cannot be reused')
        print('Reusing locked environment.', flush=True)
        return target
    target = Path(tempfile.mkdtemp(prefix=key[:12] + '-', dir=environments)).resolve()
    print('Installing locked packages and custom nodes on the RunPod volume.', flush=True)
    try:
        installer(config, target, workspace)
        if not (target / 'installed.json').is_file() or not (target / 'venv/bin/python').is_file():
            raise RuntimeError('Installer did not finish verification')
        temporary = record.with_suffix('.tmp')
        temporary.write_text(json.dumps({'fingerprint': key, 'environment': target.name}), encoding='utf-8')
        temporary.replace(record)
    except BaseException:
        # The fresh attempt is isolated; rmtree does not follow model symlinks.
        if target.parent == environments.resolve():
            shutil.rmtree(target)
        raise
    return target


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, default=Path('/opt/scail'))
    parser.add_argument('--workspace', type=Path, default=Path('/workspace'))
    args = parser.parse_args()
    state = args.workspace / '.scail'
    target = ensure(args.config, state, args.workspace)
    current = state / 'current'
    pending = state / 'current.new'
    pending.unlink(missing_ok=True)
    pending.symlink_to(target, target_is_directory=True)
    pending.replace(current)
    print('RunPod environment ready.', flush=True)


if __name__ == '__main__':
    main()
