#!/usr/bin/env python3
"""Read-only parser for Android boot (v3/v4) and vendor_boot (v3/v4) image
headers. Prints key=value lines; never modifies its input.

usage: bootimg_info.py IMAGE [IMAGE...]
"""
import struct
import sys


def os_version(v):
    if v == 0:
        return "0", "0"
    ver, lvl = v >> 11, v & 0x7FF
    a, b, c = (ver >> 14) & 0x7F, (ver >> 7) & 0x7F, ver & 0x7F
    y, m = (lvl >> 4) + 2000, lvl & 0xF
    return f"{a}.{b}.{c}", f"{y}-{m:02d}"


def cstr(b):
    return b.split(b"\0", 1)[0].decode("utf-8", "replace")


def boot(d):
    (kernel_size, ramdisk_size, osv, header_size) = struct.unpack_from("<4I", d, 8)
    header_version = struct.unpack_from("<I", d, 40)[0]
    out = {
        "type": "boot",
        "header_version": header_version,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "header_size": header_size,
        "os_version": os_version(osv)[0],
        "os_patch_level": os_version(osv)[1],
    }
    if header_version >= 3:
        out["cmdline"] = cstr(d[44:44 + 1536])
        if header_version >= 4:
            out["signature_size"] = struct.unpack_from("<I", d, 44 + 1536)[0]
        page = 4096
        koff = page
        out["kernel_magic_arm64"] = d[koff + 56:koff + 60] == b"ARMd"
    return out


def vendor_boot(d):
    hv, page, kaddr, raddr, vrsize = struct.unpack_from("<5I", d, 8)
    o = 28
    cmdline = cstr(d[o:o + 2048]); o += 2048
    tags, = struct.unpack_from("<I", d, o); o += 4
    name = cstr(d[o:o + 16]); o += 16
    hsize, dtb_size = struct.unpack_from("<2I", d, o); o += 8
    dtb_addr, = struct.unpack_from("<Q", d, o); o += 8
    out = {
        "type": "vendor_boot",
        "header_version": hv,
        "page_size": page,
        "kernel_addr": hex(kaddr),
        "ramdisk_addr": hex(raddr),
        "tags_addr": hex(tags),
        "dtb_addr": hex(dtb_addr),
        "vendor_ramdisk_size": vrsize,
        "dtb_size": dtb_size,
        "header_size": hsize,
        "product_name": name,
        "vendor_cmdline": cmdline,
    }
    if hv >= 4:
        tsize, tnum, tesize, bcsize = struct.unpack_from("<4I", d, o)
        out.update(ramdisk_table_size=tsize, ramdisk_table_entries=tnum,
                   ramdisk_table_entry_size=tesize, bootconfig_size=bcsize)
    # DTB section: count concatenated FDT blobs
    al = lambda x: (x + page - 1) // page * page
    dtb_off = al(hsize) + al(vrsize)
    blob, n, p = d[dtb_off:dtb_off + dtb_size], 0, 0
    while p + 8 <= len(blob) and blob[p:p + 4] == b"\xd0\x0d\xfe\xed":
        n += 1
        p += struct.unpack_from(">I", blob, p + 4)[0]
    out["dtb_count"] = n
    return out


def main():
    for path in sys.argv[1:]:
        with open(path, "rb") as f:
            d = f.read(64 << 20)
        magic = d[:8]
        if magic == b"ANDROID!":
            info = boot(d)
        elif magic == b"VNDRBOOT":
            info = vendor_boot(d)
        else:
            print(f"# {path}: unknown magic {magic!r}")
            continue
        print(f"# {path}")
        for k, v in info.items():
            print(f"{k}={v}")


if __name__ == "__main__":
    main()
