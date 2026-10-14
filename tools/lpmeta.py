#!/usr/bin/env python3
"""Print the extents of a logical partition in an Android super partition.

    lpmeta.py SUPER [NAME]

Reads the liblp metadata (geometry + primary metadata) read-only: metadata
slot 0 for names ending in _a, slot 1 for _b (slot 0 for the listing).
Without NAME it lists all logical partitions and their sizes. With NAME it
prints a device-mapper table (512-byte sectors) mapping the partition
linearly onto SUPER, for `dmsetup create --readonly`.
"""
import struct
import sys

LP_RESERVED = 4096
GEOMETRY_SIZE = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030


def read_metadata(f, slot):
    f.seek(LP_RESERVED)
    geo = f.read(GEOMETRY_SIZE)
    magic, _size = struct.unpack_from("<II", geo, 0)
    if magic != GEOMETRY_MAGIC:
        sys.exit("no liblp geometry (not a super partition?)")
    max_size, _slots, _block = struct.unpack_from("<III", geo, 40)
    f.seek(LP_RESERVED + 2 * GEOMETRY_SIZE + slot * max_size)
    md = f.read(max_size)
    magic, major, _minor, header_size = struct.unpack_from("<IHHI", md, 0)
    if magic != HEADER_MAGIC or major != 10:
        sys.exit("unsupported liblp metadata")
    tables = md[header_size:]
    descs = struct.unpack_from("<12I", md, 80)  # partitions, extents, groups, block devices

    def table(i):
        off, num, size = descs[3 * i:3 * i + 3]
        return [tables[off + n * size: off + (n + 1) * size] for n in range(num)]

    parts = []
    for p in table(0):
        name = p[:36].split(b"\0", 1)[0].decode()
        _attr, first, num, _group = struct.unpack_from("<IIII", p, 36)
        parts.append((name, first, num))
    extents = [struct.unpack_from("<QIQI", e, 0) for e in table(1)]
    devices = [d[24:60].split(b"\0", 1)[0].decode() for d in table(3)]
    return parts, extents, devices


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        name = sys.argv[2] if len(sys.argv) == 3 else ""
        parts, extents, devices = read_metadata(f, 1 if name.endswith("_b") else 0)
    if len(devices) != 1:
        sys.exit("super spans several block devices: %s" % devices)
    if len(sys.argv) == 2:
        for name, first, num in parts:
            sectors = sum(extents[i][0] for i in range(first, first + num))
            print("%-24s %10d MiB" % (name, sectors * 512 >> 20))
        return
    for name, first, num in parts:
        if name != sys.argv[2] or name.endswith("-cow"):
            continue
        if num == 0:
            sys.exit("%s has no extents" % name)
        start = 0
        for i in range(first, first + num):
            sectors, kind, data, _src = extents[i]
            if kind == 0:
                print("%d %d linear %s %d" % (start, sectors, sys.argv[1], data))
            else:
                print("%d %d zero" % (start, sectors))
            start += sectors
        return
    sys.exit("no logical partition %s" % sys.argv[2])


if __name__ == "__main__":
    main()
