#!/usr/bin/python3 -I
"""apmget.py IID PID SIZE [WORD...]: read a module parameter through the q6apm raw debugfs file"""
import os, struct, sys
RAW = "/sys/kernel/debug/q6apm_raw"
iid, pid, size = (int(x, 0) for x in sys.argv[1:4])
pre = b"".join(struct.pack("<I", int(x, 0)) for x in sys.argv[4:])
body = struct.pack("<IIII", iid, pid, size, 0) + pre + bytes(size - len(pre))
pl = struct.pack("<IIII", 0, 0, 0, len(body)) + body
fd = os.open(RAW, os.O_WRONLY)
try:
    os.write(fd, struct.pack("<I", 0x01001007) + pl)
    ok = "ok"
except OSError as e:
    ok = str(e)
os.close(fd)
out = open(RAW).read().split("\n")
print(f"get iid {iid:#x} pid {pid:#x}: {ok}; {out[0]}; rsp: {' '.join(out[1:]).strip()}")
