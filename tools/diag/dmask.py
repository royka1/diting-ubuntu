#!/usr/bin/python3 -I
"""send DIAG control F3 masks (all levels) to a peripheral control port:
dmask.py NODE PORT first-last ..."""
import socket, struct, sys
AF_QIPCRTR = 42
VALID = sys.argv[1] == "-v"
if VALID:
    sys.argv.pop(1)
node, port = int(sys.argv[1]), int(sys.argv[2])
s = socket.socket(AF_QIPCRTR, socket.SOCK_DGRAM)
for r in sys.argv[3:]:
    a, b = (int(x) for x in r.split("-"))
    # F3_MASK_V2 (11): stream 1, ALL_ENABLED (2), mode 0, range, 1 mask word
    if VALID:
        # status VALID (1): one mask word per SSID
        n = b - a + 1
        body = struct.pack("<BBBHHI", 1, 1, 0, a, b, n) + b"\xff\xff\xff\xff" * n
    else:
        body = struct.pack("<BBBHHII", 1, 2, 0, a, b, 1, 0xffffffff)
    s.sendto(struct.pack("<II", 11, len(body)) + body, (node, port))
    print("mask", a, b, flush=True)
