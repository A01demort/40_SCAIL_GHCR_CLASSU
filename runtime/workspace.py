"""Restore image files hidden by a fresh RunPod /workspace volume."""
from pathlib import Path
import os
import shutil
import tempfile


def copy_missing(source, target):
    """Merge seed files without overwriting persistent user data."""
    if target.exists() or target.is_symlink():
        if source.is_dir() and target.is_dir():
            for child in source.iterdir():
                copy_missing(child, target / child.name)
        return
    if source.is_symlink():
        target.symlink_to(os.readlink(source))
    elif source.is_dir():
        # Copy a fresh subtree without a remote stat/rename for every file.
        # Publish only a complete tree; interruption cannot leave a partial target.
        with tempfile.TemporaryDirectory(prefix='.scail-stage-', dir=target.parent) as folder:
            staged = Path(folder) / 'tree'
            shutil.copytree(source, staged, symlinks=True)
            os.replace(staged, target)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix='.scail-copy-', dir=target.parent)
        os.close(descriptor)
        try:
            shutil.copy2(source, temporary)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def prepare_workspace(seed=Path('/opt/scail-workspace'), workspace=Path('/workspace')):
    if not (seed / 'ComfyUI/main.py').is_file():
        raise RuntimeError('ComfyUI image seed is missing: ' + str(seed))
    workspace.mkdir(parents=True, exist_ok=True)
    copy_missing(seed / 'A1', workspace / 'A1')
    core = workspace / 'ComfyUI'
    if not (core / 'main.py').is_file():
        core.mkdir(parents=True, exist_ok=True)
        print('SCAIL: initializing mounted workspace from the image seed', flush=True)
        # Write main.py last so an interrupted first copy resumes on restart.
        for child in (seed / 'ComfyUI').iterdir():
            if child.name != 'main.py':
                copy_missing(child, core / child.name)
        copy_missing(seed / 'ComfyUI/main.py', core / 'main.py')
    for name in ('init_or_check_nodes.sh', 'startup_banner.sh',
                 'SCAIL_down_a1.sh', 'Wan2.1_Vace_a1.sh'):
        if not (workspace / 'A1' / name).is_file():
            raise RuntimeError('Workspace startup file is missing: ' + name)
    print('SCAIL: persistent workspace ready', flush=True)


if __name__ == '__main__':
    # Both RunPod clouds use the same initialization, without cloud-specific flags.
    # Lock the mounted volume so two containers cannot seed it simultaneously.
    import fcntl
    root = Path('/workspace')
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.scail-workspace.lock').open('a') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        prepare_workspace(workspace=root)
