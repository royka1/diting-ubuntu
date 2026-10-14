#!/usr/bin/python3 -I
"""Bring-up experiment: open the vendor voice-call subgraphs on the ADSP
through the q6apm raw debugfs interface (local debug patch), using the
graph and calibration blobs that acdb-query dumped from the phone's ACDB.

  voice-raw.py DIR open|start|stop|close [--sgs b0000040,b0000041,...]

DIR holds sg_<id>.spf, conn.spf, cal_<id>.p (persistent, VCPM tables) and
cal_<id>.np (non-persistent) as written by "acdb-query ... graph/cal".
Module instances of the vendor device subgraph are remapped to the Diting
topology (IID_MAP); links to modules that are not opened are dropped.
"""
import glob
import os
import struct
import sys

RAW = "/sys/kernel/debug/q6apm_raw"

APM_CMD_GRAPH_OPEN = 0x01001000
APM_CMD_GRAPH_PREPARE = 0x01001001
APM_CMD_GRAPH_START = 0x01001002
APM_CMD_GRAPH_STOP = 0x01001003
APM_CMD_GRAPH_CLOSE = 0x01001004
APM_CMD_SET_CFG = 0x01001006
APM_CMD_REGISTER_CFG = 0x01001008
RAW_MAP, RAW_FILL = 0xFFFF0001, 0xFFFF0002

APM_IID = 1
PID_SG_CFG, PID_CONT_CFG, PID_MOD_LIST = 0x08001001, 0x08001000, 0x08001002
PID_MOD_PROP, PID_MOD_CONN, PID_SG_LIST = 0x08001003, 0x08001004, 0x08001005
PID_CTRL_LINK = 0x08001061
VCPM_IID = 4
VCPM_PARAM_ID_VSID = 0x080011BC
VSID_VOICEMMODE1 = 0x11C05000
PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT = 0x08001024

# vendor device subgraph module -> Diting topology module
IID_MAP = {
    0x40E1: 0x6060,   # SAL
    0x416A: 0x6062,   # splitter
}
# MFC modules that feed the device subgraph: (iid, rate, bits, channels)
RX_MFC = [(0x41DD, 48000, 16, 2), (0x465B, 48000, 16, 2)]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def params(blob):
    """split an APM payload into (iid, pid, payload) tuples"""
    out, o = [], 0
    while o + 16 <= len(blob):
        iid, pid, size, _ = struct.unpack_from("<IIII", blob, o)
        o += 16
        out.append((iid, pid, blob[o:o + size]))
        o += (size + 7) & ~7
    return out


def param(iid, pid, payload):
    pad = (-len(payload)) % 8
    return struct.pack("<IIII", iid, pid, len(payload), 0) + payload + b"\0" * pad


def entries(pid, payload):
    """split a graph-open list parameter into its raw entries"""
    n, o, out = u32(payload, 0), 4, []
    for _ in range(n):
        start = o
        if pid in (PID_SG_CFG, PID_CONT_CFG, PID_MOD_PROP):
            nprop = u32(payload, o + 4)
            o += 8
            for _ in range(nprop):
                o += 8 + u32(payload, o + 4)
        elif pid == PID_MOD_LIST:
            o += 12 + 8 * u32(payload, o + 8)
        elif pid == PID_MOD_CONN:
            o += 16
        elif pid == PID_CTRL_LINK:
            nprop = u32(payload, o + 16)
            o += 20
            for _ in range(nprop):
                o += 8 + u32(payload, o + 4)
        out.append(bytearray(payload[start:o]))
    return out


def strip_props(e, keep):
    """keep only the listed properties of a sub-graph/container entry"""
    n, o, out = u32(e, 4), 8, b""
    cnt = 0
    for _ in range(n):
        pid, sz = struct.unpack_from("<II", e, o)
        if pid in keep:
            out += e[o:o + 8 + sz]
            cnt += 1
        o += 8 + sz
    return bytearray(struct.pack("<II", u32(e, 0), cnt) + out)


class Graph:
    def __init__(self, d, sgs):
        self.sgs = sgs
        self.lists = {p: [] for p in (PID_SG_CFG, PID_CONT_CFG, PID_MOD_LIST,
                                      PID_MOD_PROP, PID_MOD_CONN, PID_CTRL_LINK)}
        self.extra = []
        seen_cont = set()
        modules = set()
        blobs = [open(f"{d}/sg_{sg:08x}.spf", "rb").read() for sg in sgs]
        for blob in blobs:
            for iid, pid, pl in params(blob):
                if iid == APM_IID and pid == PID_MOD_LIST:
                    for e in entries(pid, pl):
                        for i in range(u32(e, 8)):
                            modules.add(u32(e, 16 + 8 * i))
        excl = {int(x, 16) for x in os.environ.get("EXCLUDE", "").split(",") if x}
        self.excl = excl
        modules -= excl
        self.modules = modules
        for blob in blobs + [open(f, "rb").read() for f in sorted(glob.glob(f"{d}/conn*.spf"))]:
            for iid, pid, pl in params(blob):
                if iid != APM_IID:
                    self.extra.append((iid, pid, pl))
                    continue
                for e in entries(pid, pl):
                    if pid == PID_CONT_CFG:
                        cid = u32(e, 0)
                        if cid in seen_cont:
                            continue
                        seen_cont.add(cid)
                        if os.environ.get("STRIP_CONT"):
                            e = strip_props(e, {0x08001011, 0x08001012, 0x08001013, 0x08001014})
                    if pid == PID_SG_CFG and os.environ.get("STRIP_SG"):
                        e = strip_props(e, {0x0800100E, 0x0800100F, 0x08001010})
                    if pid == PID_MOD_LIST and self.excl:
                        n = u32(e, 8)
                        mods = [e[12 + 8 * i:20 + 8 * i] for i in range(n)]
                        mods = [m for m in mods if u32(m, 4) not in self.excl]
                        if not mods:
                            continue
                        e = bytearray(e[:8] + struct.pack("<I", len(mods)) + b"".join(mods))
                    if pid == PID_MOD_PROP and u32(e, 0) in self.excl:
                        continue
                    if pid in (PID_MOD_CONN, PID_CTRL_LINK):
                        e = self.remap_link(e)
                        if e is None:
                            continue
                    self.lists[pid].append(e)

    def known(self, iid):
        return iid in self.modules or iid in IID_MAP.values()

    def remap_link(self, e):
        a, b = u32(e, 0), u32(e, 8)
        a, b = IID_MAP.get(a, a), IID_MAP.get(b, b)
        if not (self.known(a) and self.known(b)):
            print(f"  drop link {u32(e, 0):#x} -> {u32(e, 8):#x}")
            return None
        struct.pack_into("<I", e, 0, a)
        struct.pack_into("<I", e, 8, b)
        return e

    def open_payload(self):
        p = b""
        for pid, ents in self.lists.items():
            if pid == PID_CTRL_LINK and os.environ.get("NOCTRL"):
                continue
            if ents:
                p += param(APM_IID, pid, struct.pack("<I", len(ents)) + b"".join(ents))
        if not os.environ.get("NOEXTRA"):
            for iid, pid, pl in self.extra:
                p += param(iid, pid, pl)
        return p

    def sg_list(self):
        return param(APM_IID, PID_SG_LIST,
                     struct.pack(f"<I{len(self.sgs)}I", len(self.sgs), *self.sgs))


def raw(opcode, payload=b""):
    fd = os.open(RAW, os.O_WRONLY)
    try:
        os.write(fd, struct.pack("<I", opcode) + payload)
        ok = True
    except OSError as e:
        ok = False
        print(f"  0x{opcode:08x}: {e}")
    finally:
        os.close(fd)
    status = open(RAW).read().split("\n")[0]
    print(f"  0x{opcode:08x} [{len(payload)} B]: {'ok' if ok else 'FAILED'} ({status})")
    return ok, status


OOB_LIMIT = 3072   # in-band GPR packets are limited to about 4 KiB
OOB_OFFSET = 0x20000


def inband(opcode, payload):
    if len(payload) <= OOB_LIMIT:
        return raw(opcode, struct.pack("<IIII", 0, 0, 0, len(payload)) + payload)
    # out of band, through the shared buffer (upper part reserved for this)
    handle, iova = shm_info()
    if not handle:
        raw(RAW_MAP, struct.pack("<I", 0x40000))
        handle, iova = shm_info()
    for i in range(0, len(payload), 32768):
        raw(RAW_FILL, struct.pack("<I", OOB_OFFSET + i) + payload[i:i + 32768])
    a = iova + OOB_OFFSET
    return raw(opcode, struct.pack("<IIII", a & 0xFFFFFFFF, a >> 32, handle, len(payload)))


def shm_info():
    f = open(RAW).read().split()
    return int(f[3], 16), int(f[5], 16)   # handle, iova


def register_persistent(d, sgs):
    blobs = []
    for sg in sgs:
        f = f"{d}/cal_{sg:08x}.p"
        if os.path.exists(f):
            b = open(f, "rb").read()
            # AcdbSgIdPersistData: sg_id, size, then the parameters
            blobs.append((sg, b[8:8 + u32(b, 4)]))
    if not blobs:
        return
    total = sum((len(b) + 4095) & ~4095 for _, b in blobs)
    handle, iova = shm_info()
    if not handle:
        raw(RAW_MAP, struct.pack("<I", total))
        handle, iova = shm_info()
    off = 0
    for sg, b in blobs:
        for i in range(0, len(b), 32768):
            raw(RAW_FILL, struct.pack("<I", off + i) + b[i:i + 32768])
        hdr = struct.pack("<IIII", (iova + off) & 0xFFFFFFFF, (iova + off) >> 32, handle, len(b))
        print(f"register persistent cal {sg:#x} ({len(b)} B)")
        raw(APM_CMD_REGISTER_CFG, hdr)
        off += (len(b) + 4095) & ~4095


def set_nonpersistent(d, sgs):
    for sg in sgs:
        f = f"{d}/cal_{sg:08x}.np"
        if os.path.exists(f):
            print(f"set non-persistent cal {sg:#x}")
            inband(APM_CMD_SET_CFG, open(f, "rb").read())


def mfc_cfg(iid, rate, bits, ch):
    return param(iid, PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT,
                 struct.pack(f"<IHH{ch}H", rate, bits, ch, *range(1, ch + 1)))


def main():
    d, op = sys.argv[1], sys.argv[2]
    sgs = sorted(int(x, 16) for x in (sys.argv[4].split(",") if len(sys.argv) > 4 else
                 [os.path.basename(f)[3:11] for f in glob.glob(f"{d}/sg_*.spf")]))
    g = Graph(d, sgs)
    if op == "open":
        print("graph open:", ", ".join(f"{s:#x}" for s in sgs))
        if not inband(APM_CMD_GRAPH_OPEN, g.open_payload())[0]:
            sys.exit(1)
        if os.environ.get("OPENONLY"):
            return
        print("VSID")
        inband(APM_CMD_SET_CFG, param(VCPM_IID, VCPM_PARAM_ID_VSID, struct.pack("<I", VSID_VOICEMMODE1)))
        register_persistent(d, sgs)
        set_nonpersistent(d, sgs)
        print("cal keys + MFC")
        cfg = param(VCPM_IID, 0x0800116B, struct.pack("<II6I", VSID_VOICEMMODE1, 3,
                                                     0x08001166, 3, 0x080011B6, 0, 0x08001167, 0))
        for m in RX_MFC:
            if m[0] in g.modules:
                cfg += mfc_cfg(*m)
        inband(APM_CMD_SET_CFG, cfg)
    elif op == "start":
        inband(APM_CMD_GRAPH_PREPARE, g.sg_list())
        inband(APM_CMD_GRAPH_START, g.sg_list())
    elif op == "stop":
        inband(APM_CMD_GRAPH_STOP, g.sg_list())
    elif op == "close":
        inband(APM_CMD_GRAPH_CLOSE, g.sg_list())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
