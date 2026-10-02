"""Bound the optional source reader and preserve reasons when it cannot run."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def read(arguments, timeout=60):
    command = [sys.executable, '-B', str(Path(__file__).with_name('static-guidelines.py'))] + arguments
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        if result.stderr:
            print(result.stderr, file=sys.stderr, end='')
        if result.returncode:
            return {'_reader_error': 'reader failed (exit %d); see stderr' % result.returncode}
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise ValueError('reader result is not an object')
        return value
    except subprocess.TimeoutExpired:
        reason = 'reader timeout after %g seconds' % timeout
    except (OSError, ValueError) as exc:
        reason = 'reader failed: ' + type(exc).__name__
    print(reason, file=sys.stderr)
    return {'_reader_error': reason}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--timeout', type=float, default=60)
    args, arguments = parser.parse_known_args()
    if not 0 < args.timeout <= 60:
        parser.error('timeout must be positive and at most 60 seconds')
    print(json.dumps(read(arguments, args.timeout)))


if __name__ == '__main__':
    main()
