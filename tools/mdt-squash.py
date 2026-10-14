#!/usr/bin/python3 -I
"""Combine a split Qualcomm firmware image (NAME.mdt + NAME.bNN) into one
.mbn, like pil-squasher: the .mdt (ELF header + program headers, often also
the hash segment) goes first, every segment NN is placed at its p_offset.

  mdt-squash.py IN.mdt OUT.mbn
"""
import os
import struct
import sys


def main():
    mdt_path, out_path = sys.argv[1:3]
    base = mdt_path[:-4]
    mdt = open(mdt_path, "rb").read()
    if mdt[:4] != b"\x7fELF":
        sys.exit(f"{mdt_path}: not an ELF file")
    is64 = mdt[4] == 2
    if is64:
        phoff, = struct.unpack_from("<Q", mdt, 0x20)
        phentsize, phnum = struct.unpack_from("<HH", mdt, 0x36)
    else:
        phoff, = struct.unpack_from("<I", mdt, 0x1c)
        phentsize, phnum = struct.unpack_from("<HH", mdt, 0x2a)

    segs = []
    for i in range(phnum):
        off = phoff + i * phentsize
        if is64:
            _, _, p_offset, _, _, p_filesz = struct.unpack_from("<IIQQQQ", mdt, off)
        else:
            _, p_offset, _, _, p_filesz = struct.unpack_from("<IIIII", mdt, off)
        segs.append((i, p_offset, p_filesz))

    size = max([len(mdt)] + [o + s for _, o, s in segs])
    out = bytearray(size)
    out[:len(mdt)] = mdt
    for i, off, filesz in segs:
        if filesz == 0:
            continue
        part = f"{base}.b{i:02d}"
        if os.path.exists(part):
            data = open(part, "rb").read()
            if len(data) != filesz:
                sys.exit(f"{part}: size {len(data)} != p_filesz {filesz}")
            out[off:off + filesz] = data
        elif off + filesz <= len(mdt):
            pass  # segment already contained in the .mdt
        else:
            sys.exit(f"segment {i}: {part} missing (p_filesz {filesz})")
    open(out_path, "wb").write(out)
    print(f"{out_path}: {len(segs)} segments, {size} bytes")


if __name__ == "__main__":
    main()
