#!/usr/bin/python3 -I
"""send one non-HDLC DIAG command to a QRTR port: dcmd.py NODE PORT HEXBYTES"""
import socket, sys
AF_QIPCRTR = 42
node, port, payload = int(sys.argv[1]), int(sys.argv[2]), bytes.fromhex(sys.argv[3])
s = socket.socket(AF_QIPCRTR, socket.SOCK_DGRAM)
pkt = bytes([0x7e, 1]) + len(payload).to_bytes(2, "little") + payload + b"\x7e"
s.sendto(pkt, (node, port))
print("sent", pkt.hex())
s.settimeout(3)
try:
    while True:
        d, a = s.recvfrom(65536)
        print("reply from", a, d[:64].hex())
except socket.timeout:
    print("no (more) reply")
