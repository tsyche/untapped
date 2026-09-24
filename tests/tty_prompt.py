#!/usr/bin/env python3
"""Answer one CLI prompt through a real terminal; fail on hangs or early EOF."""
import errno
import os
import pty
import select
import signal
import sys
import time

pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])

output = bytearray()
answered = False
deadline = time.monotonic() + 15
try:
    while time.monotonic() < deadline:
        if not select.select([fd], [], [], 0.1)[0]:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError as exc:
            if exc.errno != errno.EIO:
                raise
            break
        if not chunk:
            break
        output.extend(chunk)
        if not answered and b'[Y/n]' in output:
            os.write(fd, os.environ.get('PROMPT_REPLY', 'Y\n').encode())
            answered = True
    else:
        os.kill(pid, signal.SIGKILL)
        raise SystemExit('CLI prompt timed out')
finally:
    os.close(fd)
    _, status = os.waitpid(pid, 0)
    sys.stdout.buffer.write(output)

sys.exit(os.waitstatus_to_exitcode(status) if answered else 1)
