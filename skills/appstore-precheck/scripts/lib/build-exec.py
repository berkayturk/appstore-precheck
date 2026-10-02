"""Bounded build subprocesses with isolated environment and retained diagnostics.

Adapted from the allowlisted build-exec.py process-group and environment pattern.
"""
import os
from pathlib import Path
import signal
import subprocess


def environment(home):
    home = Path(home)
    env = {'PATH': os.environ.get('PATH', '/usr/bin:/bin'), 'HOME': str(home),
           'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(home / 'tmp'), 'CI': '1',
           'COCOAPODS_DISABLE_STATS': '1', 'EXPO_NO_TELEMETRY': '1',
           'npm_config_cache': str(home / '.npm'), 'PUB_CACHE': str(home / '.pub-cache'),
           'GRADLE_USER_HOME': str(home / '.gradle'), 'LANG': 'C.UTF-8'}
    (home / 'tmp').mkdir(parents=True, exist_ok=True)
    for key in ('DEVELOPER_DIR', 'GEM_PATH'):
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def execute(command, cwd, home, log, timeout):
    proc = None
    try:
        proc = subprocess.Popen(command, cwd=cwd, env=environment(home), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True)
        output, _ = proc.communicate(timeout=timeout)
        code = proc.returncode
    except subprocess.TimeoutExpired:
        kill_group(proc); output, _ = proc.communicate(); code = 124
    except FileNotFoundError as exc:
        output, code = str(exc).encode(), 127
    except BaseException:
        if proc is not None:
            kill_group(proc); proc.wait()
        raise
    fd = os.open(str(log), os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'ab') as stream:
        stream.write(output)
    return code, output.decode('utf-8', 'replace')
