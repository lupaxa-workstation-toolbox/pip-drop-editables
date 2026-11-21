#!/usr/bin/env python3
"""Run a command on a pty, or with no controlling terminal."""

import os
import pty
import select
import subprocess
import sys


def run_pty(argv, feed):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(argv[0], argv)
    data = feed.encode()
    out = b""
    while True:
        ready, _, _ = select.select([fd], [], [], 2)
        if not ready:
            break
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
        if data and (b"Which Python?" in out or b"Uninstall these" in out):
            os.write(fd, data)
            data = b""
    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    sys.stdout.buffer.write(out)
    return code


def run_notty(argv):
    done = subprocess.run(argv, start_new_session=True, capture_output=True)
    sys.stdout.buffer.write(done.stdout)
    sys.stderr.buffer.write(done.stderr)
    return done.returncode


def command_after(argv):
    if argv and argv[0] == "--":
        return argv[1:]
    return argv


def main():
    mode = sys.argv[1]
    if mode == "--notty":
        code = run_notty(command_after(sys.argv[2:]))
    elif mode == "--feed":
        feed = sys.argv[2]
        code = run_pty(command_after(sys.argv[3:]), feed)
    else:
        print("usage: pty-run.py --notty|--feed TEXT -- command", file=sys.stderr)
        return 2
    return code


if __name__ == "__main__":
    raise SystemExit(main())
