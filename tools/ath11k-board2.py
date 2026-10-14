#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build an ath11k board-2.bin from an Android QCA6490 board data file.

    ath11k-board2.py [--mac-file wlan_mac.bin] BDF.elf OUT NAME...

Android's cnss driver loads the board data (bdwlan/bd_*.elf) itself; ath11k
looks it up by board name in board-2.bin, and Ubuntu's board-2.bin already
has a generic entry for this chip (board id 255, never programmed on
diting) that would otherwise win. Each NAME becomes one entry with the same
data.

The Xiaomi board data leaves the MAC address empty (Android sends it to the
firmware separately, which ath11k cannot do), so the firmware would report
00:00:00:00:00:00. --mac-file takes the phone's persist/qca6490/wlan_mac.bin
("wlan0=<12 hex digits>") and writes that address into the board data,
where the generic board files carry it, then corrects the checksum word so
that the XOR of all 16-bit words stays 0xffff.
"""
import argparse
import re
import struct
import sys

MAC_OFF = 0x0e   # 6 bytes, as in the generic WCN6855 board data
CSUM_OFF = 0x0a  # 16-bit checksum word


def xor16(data):
    x = 0
    for (w,) in struct.iter_unpack('<H', data[:len(data) & ~1]):
        x ^= w
    return x


def load_segment(elf):
    """Return (offset, size) of the single PT_LOAD segment of an ELF32."""
    if elf[:4] != b'\x7fELF' or elf[4] != 1:
        sys.exit('not an ELF32 board data file')
    phoff, = struct.unpack_from('<I', elf, 0x1c)
    phentsize, phnum = struct.unpack_from('<HH', elf, 0x2a)
    loads = []
    for i in range(phnum):
        p_type, p_offset, _, _, p_filesz = struct.unpack_from('<IIIII', elf, phoff + i * phentsize)
        if p_type == 1:
            loads.append((p_offset, p_filesz))
    if len(loads) != 1:
        sys.exit('expected one LOAD segment, found %d' % len(loads))
    return loads[0]


def set_mac(elf, mac):
    off, size = load_segment(elf)
    bdf = elf[off:off + size]
    if xor16(bdf) != 0xffff:
        sys.exit('board data checksum is not valid before patching')
    bdf[MAC_OFF:MAC_OFF + 6] = mac
    bdf[CSUM_OFF:CSUM_OFF + 2] = b'\0\0'
    struct.pack_into('<H', bdf, CSUM_OFF, xor16(bdf) ^ 0xffff)
    assert xor16(bdf) == 0xffff
    elf[off:off + size] = bdf


def read_mac(path):
    text = open(path, 'rb').read().decode('ascii', 'replace')
    m = re.search(r'^wlan0=([0-9A-Fa-f]{12})\s*$', text, re.M)
    if not m:
        sys.exit('%s: no wlan0=<12 hex digits> line' % path)
    mac = bytes.fromhex(m.group(1))
    if mac[0] & 1 or mac == bytes(6):
        sys.exit('%s: not a unicast address' % path)
    return mac


def ie(ie_type, data):
    return struct.pack('<II', ie_type, len(data)) + data + b'\0' * (-len(data) % 4)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--mac-file')
    ap.add_argument('bdf')
    ap.add_argument('out')
    ap.add_argument('names', nargs='+')
    a = ap.parse_args()
    elf = bytearray(open(a.bdf, 'rb').read())
    if a.mac_file:
        set_mac(elf, read_mac(a.mac_file))
    # ATH11K_BD_IE_BOARD (0) holding BOARD_NAME (0) and BOARD_DATA (1)
    out = bytearray(b'QCA-ATH11K-BOARD\0')
    out += b'\0' * (-len(out) % 4)
    for name in a.names:
        out += ie(0, ie(0, name.encode()) + ie(1, bytes(elf)))
    with open(a.out, 'wb') as f:
        f.write(out)


if __name__ == '__main__':
    main()
