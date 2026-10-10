"""Keep Manager installed while preventing queued runtime package/source changes."""
import argparse
import configparser
from pathlib import Path


def configure(user):
    manager = user / '__manager'
    for relative in ['startup-scripts/install-scripts.txt', 'startup-scripts/restore-snapshot.json', 'pip_auto_fix.list']:
        pending = manager / relative
        if pending.is_file() and pending.read_text(encoding='utf-8').strip():
            raise RuntimeError(f'Queued Manager changes are incompatible with this locked image: {relative}. Preserve the queue and use a maintenance image to update.')
    manager.mkdir(parents=True, exist_ok=True)
    path = manager / 'config.ini'
    config = configparser.ConfigParser()
    config.read(path, encoding='utf-8')
    if not config.has_section('default'):
        config.add_section('default')
    config['default'].update({'network_mode': 'offline', 'security_level': 'strong',
                              'use_uv': 'false', 'file_logging': 'false', 'db_mode': 'local'})
    with path.open('w', encoding='utf-8', newline='\n') as stream:
        config.write(stream)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--user-dir', type=Path, default=Path('/workspace/scail-user'))
    args = parser.parse_args()
    configure(args.user_dir)
    print('Manager retained; offline policy applied and no queued changes present.')
