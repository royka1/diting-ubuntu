#!/usr/bin/env python3
"""Run a shell command on the Diting debug initramfs shell (USB ACM) and
print its output. usage: acm-run.py [-d /dev/ttyACM0] [-t timeout] 'command'"""
import argparse, os, select, termios, time, uuid

ap = argparse.ArgumentParser()
ap.add_argument("-d", default="/dev/ttyACM0")
ap.add_argument("-t", type=float, default=60)
ap.add_argument("cmd")
a = ap.parse_args()

fd = os.open(a.d, os.O_RDWR | os.O_NOCTTY)
attr = termios.tcgetattr(fd)
attr[0] = attr[1] = attr[3] = 0          # raw: no iflag/oflag/lflag processing
attr[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
termios.tcsetattr(fd, termios.TCSANOW, attr)
termios.tcflush(fd, termios.TCIOFLUSH)

tag = uuid.uuid4().hex[:8]
# Markers are split with "" so the tty echo of the command never matches.
os.write(fd, f"echo BEG\"\"IN{tag}; {a.cmd}; echo EN\"\"D{tag}\n".encode())
buf, end = b"", time.time() + a.t
while time.time() < end and f"END{tag}".encode() not in buf.split(f"BEGIN{tag}".encode(), 1)[-1]:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        buf += os.read(fd, 65536)
out = buf.split(f"BEGIN{tag}".encode(), 1)[-1].split(f"END{tag}".encode(), 1)[0]
print(out.decode("utf-8", "replace").replace("\r\n", "\n").strip("\n"))
