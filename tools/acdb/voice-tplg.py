#!/usr/bin/python3 -I
"""Generate alsatplg sections for a voice call front end from the vendor
voice graph that acdb-query dumped from the phone's ACDB.

  voice-tplg.py [--no-devpp] [--loopback] RXDIR TXDIR > voice.conf

RXDIR/TXDIR hold sg_<id>.spf, conn.spf and cal_<id>.{p,np} for the voice
call RX (downlink) and TX (uplink) graphs. As on Android (PAL opens an RX
and a TX hostless session), the result is two AudioReach graphs: RX on
front end MultiMedia3 (playback, feeds the TERTIARY_TDM_RX_0 device mixer)
and TX on MultiMedia4 (capture, takes the TX_CODEC_DMA_TX_3 device through
the "MultiMedia4 Mixer"). The TX graph is opened first; control links
between RX and TX modules are opened with the RX graph. Calibration and VCPM settings are
module configuration arrays (SND_SOC_AR_TPLG_MODULE_CFG_TYPE): persistent
VCPM tables, graph-open parameters (control links, VCPM voice config) and
plain set-config parameters (VSID, cal keys, media formats).

The generated file contains Xiaomi/Qualcomm calibration: local use only.
"""
import glob
import os
import struct
import sys

FE = 2                      # FRONTEND_DAI_MULTIMEDIA3, RX graph id
FE_NAME = "MultiMedia3"
FE_TX = 3                   # FRONTEND_DAI_MULTIMEDIA4, TX graph id
FE_TX_NAME = "MultiMedia4"
PREFIX = "voice"
RX_SGS = [0xB0000040, 0xB0000041, 0xB0000044, 0xB0000045]
TX_SGS = [0xB00000B1, 0xB000003F]
# Device post-processing sub-graphs (RX chain, TX Fluence ECNS) use modules
# that the ADSP loads dynamically through the audio PD (FastRPC). Without
# that, leave them out (--no-devpp) and bridge their ends directly.
DEVPP_SGS = {0xB0000044, 0xB00000B1}
DEVPP_BRIDGES = [(0x41B8, 1, 0x41DE, 2)]   # stream RX logger -> TRM
TX_HEAD_NO_DEVPP = 0x47B8                  # stream TX entry (logger)
EXCLUDE_CONTAINERS = {0xE000015A}   # tone/ICMD branch into the vendor SAL
RX_HEAD, RX_TAIL = 0x41B1, 0x416A   # mailbox from the modem, into the device
# Echo reference: as in the vendor speaker device sub-graph, a splitter at
# the end of the RX path feeds the device (output 1) and the TX device
# post-processing's reference input (0x4448 port 4, output 3); without it
# the TX chain (EC sync, smart sync, Fluence ECNS) has no reference.
ECREF_SPLITTER = {"iid": 0x416A, "id": 0x07001011, "after": 0x41DF, "sg": 0xB0000045,
                  "cont": 0xE0000036, "ref": (0x4448, 4)}
TX_HEAD, TX_TAIL = 0x4448, 0x41B0   # from the mics, mailbox to the modem
# the device subgraphs of the Diting topology
SPEAKER_MIXER = "TERTIARY_TDM_RX_0 Audio Mixer"
MIC_DEVICE = "TX_CODEC_DMA_TX_3"
MIC_DEVICE_WIDGET = "device120.logger1"

APM_IID, VCPM_IID = 1, 4
PID_SG_CFG, PID_CONT_CFG, PID_MOD_LIST = 0x08001001, 0x08001000, 0x08001002
PID_MOD_PROP, PID_MOD_CONN, PID_CTRL_LINK = 0x08001003, 0x08001004, 0x08001061
PROP_PORT_INFO = 0x08001015
SG_PROP_PERF, SG_PROP_DIR, SG_PROP_SID = 0x0800100E, 0x0800100F, 0x08001010
CONT_TYPE, CONT_POS, CONT_STACK, CONT_DOMAIN = 0x08001011, 0x08001012, 0x08001013, 0x08001014
VCPM_PARAM_ID_VSID = 0x080011BC
VCPM_PARAM_ID_CAL_KEYS = 0x0800116B
VCPM_PARAM_ID_TX_DEV_PP_CHANNEL_INFO = 0x08001310
VCPM_CAL_KEY_ID_VOLUME_LEVEL, VCPM_CAL_KEY_ID_VOL_BOOST, VCPM_CAL_KEY_ID_BWE = \
    0x08001166, 0x080011B6, 0x08001167
PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT = 0x08001024
VSID = 0x11C05000           # VOICEMMODE1
# --loopback: vocoder packet loopback inside the ADSP (no modem), for testing
# the voice graph: the TX stream is played back on RX after LOOPBACK_DELAY_MS
VSID_LOOPBACK = 0x12006000  # VOICELBMMODE1
VCPM_PARAM_ID_VOC_PKT_LOOPBACK_DELAY = 0x08001311
LOOPBACK_DELAY_MS = 1000
VOLUME_LEVEL = 4            # the calibration has steps 0..4 (5 has no entry: RX silent)
VOLUME_BOOST = 1            # calibrated boost variant; speakerphone was too quiet at 3 and 4
TX_CHANNELS = 2             # AMIC1 + AMIC5
RX_MFC = {0x41DD: (48000, 16, 2)}   # into the speaker device: S16, 48 kHz, 2ch
# TX media format converters at the vocoder rate. The calibration has an
# entry per vocoder sampling rate that VCPM should select from its keys;
# it does not apply them here, so the TX path ran at the device's 48 kHz
# and the encoder got 48 kHz audio (voice pitched far down, hiss). Set the
# wideband (16 kHz) entries, as the calibration has them, explicitly:
#   0x4446 device PP mic path, 0x4447 echo reference path, 0x458b stream
TX_MFC_16K = {0x4446: bytes.fromhex("803e00001000020001000200"),
              0x4447: bytes.fromhex("803e00001000ffff"),
              0x458B: bytes.fromhex("803e0000100001000300")}
CFG_TYPE = 0x01001006
CFG_SET, CFG_PERSISTENT, CFG_GRAPH_OPEN, CFG_SET_LATE, CFG_PLAYBACK_LINKS = 0, 1, 2, 3, 4
# vendor hardware endpoints -> the Diting device sub-graphs: control links
# (timing for the mailboxes, echo reference) are kept with these
EP_RX = {0x43B3: 0x6061}    # codec DMA sink -> tertiary TDM sink (device56)
EP_TX = {0x43AF: 0x6090}    # codec DMA source -> TX codec DMA 3 source (device120)
# vendor device container (RX renderer + endpoint) -> the Diting speaker
# device container (device56 in XIAOMI-DITING.m4)
CONT_MAP = {0xE0000036: 0x4006}


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def params(blob):
    out, o = [], 0
    while o + 16 <= len(blob):
        iid, pid, size, _ = struct.unpack_from("<IIII", blob, o)
        o += 16
        out.append((iid, pid, bytes(blob[o:o + size])))
        o += (size + 7) & ~7
    return out


def param(iid, pid, payload):
    return struct.pack("<IIII", iid, pid, len(payload), 0) + payload + b"\0" * ((-len(payload)) % 8)


def props(b, o, n):
    out = {}
    for _ in range(n):
        pid, sz = struct.unpack_from("<II", b, o)
        out[pid] = struct.unpack_from(f"<{sz // 4}I", b, o + 8)
        o += 8 + sz
    return o, out


class Voice:
    def __init__(self, rxdir, txdir, devpp=True):
        global RX_SGS, TX_SGS, TX_HEAD
        if not devpp:
            RX_SGS = [g for g in RX_SGS if g not in DEVPP_SGS]
            TX_SGS = [g for g in TX_SGS if g not in DEVPP_SGS]
            TX_HEAD = TX_HEAD_NO_DEVPP
        self.sgs, self.conts, self.mods = {}, {}, {}
        self.conns, self.ctrl = [], []
        # per direction ("rx"/"tx"): graph open extras, calibration
        self.extra = {"rx": [], "tx": []}   # (iid, pid, payload) graph open
        self.cal_p = {"rx": [], "tx": []}
        self.cal_np = {"rx": [], "tx": []}
        for d, sgs, dr in ((rxdir, RX_SGS, "rx"), (txdir, TX_SGS, "tx")):
            for sg in sgs:
                self.load(open(f"{d}/sg_{sg:08x}.spf", "rb").read(), dr)
                for kind, lst in (("p", self.cal_p[dr]), ("np", self.cal_np[dr])):
                    f = f"{d}/cal_{sg:08x}.{kind}"
                    if os.path.exists(f):
                        b = open(f, "rb").read()
                        lst.append(b[8:8 + u32(b, 4)] if kind == "p" else b)
            self.load(open(f"{d}/conn.spf", "rb").read(), dr)
        # drop what is not opened: other subgraphs, excluded containers
        self.mods = {k: v for k, v in self.mods.items()
                     if v["cont"] not in EXCLUDE_CONTAINERS}
        keep = lambda a, b: a in self.mods and b in self.mods
        if not devpp:
            self.conns += DEVPP_BRIDGES
        e = ECREF_SPLITTER
        if devpp and e["after"] in self.mods:
            self.mods[e["iid"]] = {"id": e["id"], "sg": e["sg"], "cont": e["cont"],
                                   "ports": (1, 2)}
            self.conns += [(e["after"], 1, e["iid"], 2), (e["iid"], 3) + e["ref"]]
        self.conns = sorted(set(c for c in self.conns if keep(c[0], c[2])))
        seen, ctrl, self.ctrl_play = set(), [], []
        eps = {**EP_RX, **EP_TX}
        for c in self.ctrl:
            if c[:4] in seen:
                continue
            seen.add(c[:4])
            if keep(c[0], c[2]):
                ctrl.append(c)
                continue
            a, b = c[0], c[2]
            if (a in eps and b in self.mods) or (b in eps and a in self.mods):
                e = bytearray(c[4])
                struct.pack_into("<I", e, 0, eps.get(a, a))
                struct.pack_into("<I", e, 8, eps.get(b, b))
                c = (eps.get(a, a), c[1], eps.get(b, b), c[3], bytes(e))
                (self.ctrl_play if a in EP_RX or b in EP_RX else ctrl).append(c)
        self.ctrl = ctrl
        # Containers shared by several sub-graphs keep their id: the kernel
        # gives each sub-graph its own copy (DSP-side it is one container).
        # The RX renderer must share the speaker endpoint's container: it
        # makes its render decisions on the endpoint's signal triggers.
        for m in self.mods.values():
            if m["cont"] in CONT_MAP:
                m["cont"] = CONT_MAP[m["cont"]]
        for c, nc in CONT_MAP.items():
            if c in self.conts:
                self.conts.setdefault(nc, self.conts[c])
        # parameters for modules that are not opened are dropped
        for dr in self.cal_np:
            self.cal_np[dr] = [b"".join(param(i, p, pl) for i, p, pl in params(b)
                                        if i == VCPM_IID or i in self.mods)
                               for b in self.cal_np[dr]]

    def dir_of(self, iid):
        return "rx" if self.mods[iid]["sg"] in RX_SGS else "tx"

    def ctrl_of(self, dr):
        """control links opened with graph dr: TX-only links with TX, the
        rest (RX-only, RX<->TX) with the RX graph, which opens second"""
        def d(c):
            ends = {self.dir_of(i) for i in (c[0], c[2]) if i in self.mods}
            return "tx" if ends == {"tx"} else "rx"
        return [c for c in self.ctrl if d(c) == dr]

    def load(self, blob, dr):
        for iid, pid, p in params(blob):
            if iid != APM_IID:
                self.extra[dr].append((iid, pid, p))
                continue
            n, o = u32(p, 0), 4
            for _ in range(n):
                if pid == PID_SG_CFG:
                    sg, np_ = struct.unpack_from("<II", p, o)
                    o, pr = props(p, o + 8, np_)
                    self.sgs[sg] = pr
                elif pid == PID_CONT_CFG:
                    c, np_ = struct.unpack_from("<II", p, o)
                    o, pr = props(p, o + 8, np_)
                    self.conts.setdefault(c, pr)
                elif pid == PID_MOD_LIST:
                    sg, c, nm = struct.unpack_from("<III", p, o)
                    o += 12
                    for _ in range(nm):
                        mid, miid = struct.unpack_from("<II", p, o)
                        o += 8
                        self.mods[miid] = {"id": mid, "sg": sg, "cont": c, "ports": (1, 1)}
                elif pid == PID_MOD_PROP:
                    miid, np_ = struct.unpack_from("<II", p, o)
                    o, pr = props(p, o + 8, np_)
                    if miid in self.mods and PROP_PORT_INFO in pr:
                        self.mods[miid]["ports"] = pr[PROP_PORT_INFO][:2]
                elif pid == PID_MOD_CONN:
                    self.conns.append(struct.unpack_from("<IIII", p, o))
                    o += 16
                elif pid == PID_CTRL_LINK:
                    a = struct.unpack_from("<IIIII", p, o)
                    end = o + 20
                    for _ in range(a[4]):
                        end += 8 + u32(p, end + 4)
                    self.ctrl.append(a[:4] + (bytes(p[o:end]),))
                    o = end

    # --- configuration blobs -------------------------------------------
    def graph_open_params(self, dr):
        out = b""
        ctrl = self.ctrl_of(dr)
        if ctrl:
            out += param(APM_IID, PID_CTRL_LINK,
                         struct.pack("<I", len(ctrl)) + b"".join(c[4] for c in ctrl))
        for iid, pid, p in self.extra[dr]:
            out += param(iid, pid, p)
        return out

    def playback_links(self):
        if not self.ctrl_play:
            return b""
        # one parameter per link: each is sent as its own graph open
        return b"".join(param(APM_IID, PID_CTRL_LINK, struct.pack("<I", 1) + c[4])
                        for c in self.ctrl_play)

    def set_params(self, dr):
        # as PAL: VSID on the RX session, the TX channel info on TX
        out = b"".join(self.cal_np[dr])
        if dr == "tx":
            out += param(VCPM_IID, VCPM_PARAM_ID_TX_DEV_PP_CHANNEL_INFO,
                         struct.pack("<II", VSID, TX_CHANNELS))
            for iid, pl in TX_MFC_16K.items():
                if iid in self.mods:
                    out += param(iid, PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT, pl)
            return out
        out += param(VCPM_IID, VCPM_PARAM_ID_VSID, struct.pack("<I", VSID))
        if VSID == VSID_LOOPBACK:
            out += param(VCPM_IID, VCPM_PARAM_ID_VOC_PKT_LOOPBACK_DELAY,
                         struct.pack("<II", VSID, LOOPBACK_DELAY_MS))
        for iid, (rate, bits, ch) in RX_MFC.items():
            if iid in self.mods:
                out += param(iid, PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT,
                             struct.pack(f"<IHH{ch}H", rate, bits, ch, *range(1, ch + 1)))
        return out

    def set_late_params(self):
        # after the calibration tables are registered
        return param(VCPM_IID, VCPM_PARAM_ID_CAL_KEYS,
                     struct.pack("<II6I", VSID, 3, VCPM_CAL_KEY_ID_VOLUME_LEVEL, VOLUME_LEVEL,
                                 VCPM_CAL_KEY_ID_VOL_BOOST, VOLUME_BOOST, VCPM_CAL_KEY_ID_BWE, 0))


def cfg_array(kind, payload):
    return struct.pack("<IIII", 16 + len(payload), CFG_TYPE, kind, 0) + payload


DATA_CHUNK = 16384


def hexbytes(b):
    return ",".join(f"0x{x:02x}" for x in b)


def name(iid):
    return f"{PREFIX}.m{iid:04x}"


# token ids from include/uapi/sound/snd_ar_tokens.h; the upstream topology
# token list lacks the numbered link tokens
TOKENS = [("AR_TKN_DAI_INDEX", 1), ("AR_TKN_U32_SUB_GRAPH_INSTANCE_ID", 2),
          ("AR_TKN_U32_SUB_GRAPH_PERF_MODE", 3), ("AR_TKN_U32_SUB_GRAPH_DIRECTION", 4),
          ("AR_TKN_U32_SUB_GRAPH_SCENARIO_ID", 5), ("AR_TKN_U32_CONAINER_INSTANCE_ID", 100),
          ("AR_TKN_U32_CONAINER_CAPABILITY_ID", 101), ("AR_TKN_U32_CONAINER_STACK_SIZE", 102),
          ("AR_TKN_U32_CONAINER_GRAPH_POS", 103), ("AR_TKN_U32_CONAINER_PROC_DOMAIN", 104),
          ("AR_TKN_U32_MODULE_ID", 200), ("AR_TKN_U32_MODULE_INSTANCE_ID", 201),
          ("AR_TKN_U32_MODULE_MAX_IP_PORTS", 202), ("AR_TKN_U32_MODULE_MAX_OP_PORTS", 203),
          ("AR_TKN_U32_MODULE_SRC_OP_PORT_ID", 206), ("AR_TKN_U32_MODULE_DST_IN_PORT_ID", 207),
          ("AR_TKN_U32_MODULE_SRC_INSTANCE_ID", 208), ("AR_TKN_U32_MODULE_DST_INSTANCE_ID", 209)]
for n in range(1, 8):
    TOKENS += [(f"AR_TKN_U32_MODULE_SRC_OP_PORT_ID{n}", 207 + 3 * n),
               (f"AR_TKN_U32_MODULE_DST_IN_PORT_ID{n}", 208 + 3 * n),
               (f"AR_TKN_U32_MODULE_DST_INSTANCE_ID{n}", 209 + 3 * n)]


def emit(v):
    o = []
    w = o.append
    w("# Voice call graph from the vendor ACDB (generated by voice-tplg.py).")
    w("# Contains vendor calibration: local use only.\n")
    w(f'SectionVendorTokens."{PREFIX}_tokens" {{\n' +
      "\n".join(f'\t{t} "{i}"' for t, i in TOKENS) + "\n}\n")
    for sg, pr in v.sgs.items():
        if not any(m["sg"] == sg for m in v.mods.values()):
            continue
        fe = FE if sg in RX_SGS else FE_TX
        w(f'SectionVendorTuples."{PREFIX}.sg{sg:08x}_tuples" {{\n\ttokens "{PREFIX}_tokens"\n'
          f'\ttuples."word.u32_data" {{\n'
          f'\t\tAR_TKN_U32_SUB_GRAPH_INSTANCE_ID "0x{sg:08x}"\n\t\tAR_TKN_DAI_INDEX "{fe}"\n'
          f'\t\tAR_TKN_U32_SUB_GRAPH_PERF_MODE "0x{pr[SG_PROP_PERF][0]:x}"\n'
          f'\t\tAR_TKN_U32_SUB_GRAPH_DIRECTION "0x{pr[SG_PROP_DIR][0]:x}"\n'
          f'\t\tAR_TKN_U32_SUB_GRAPH_SCENARIO_ID "0x{pr[SG_PROP_SID][0]:x}"\n\t}}\n}}\n'
          f'SectionData."{PREFIX}.sg{sg:08x}_data" {{\n\ttuples "{PREFIX}.sg{sg:08x}_tuples"\n}}\n')
    for c, pr in v.conts.items():
        if not any(m["cont"] == c for m in v.mods.values()):
            continue
        w(f'SectionVendorTuples."{PREFIX}.c{c:08x}_tuples" {{\n\ttokens "{PREFIX}_tokens"\n'
          f'\ttuples."word.u32_data" {{\n'
          f'\t\tAR_TKN_U32_CONAINER_INSTANCE_ID "0x{c:08x}"\n'
          f'\t\tAR_TKN_U32_CONAINER_CAPABILITY_ID "0x{pr[CONT_TYPE][1]:x}"\n'
          f'\t\tAR_TKN_U32_CONAINER_STACK_SIZE "{pr[CONT_STACK][0]}"\n'
          f'\t\tAR_TKN_U32_CONAINER_GRAPH_POS "0x{pr[CONT_POS][0]:x}"\n'
          f'\t\tAR_TKN_U32_CONAINER_PROC_DOMAIN "0x{pr[CONT_DOMAIN][0]:x}"\n\t}}\n}}\n'
          f'SectionData."{PREFIX}.c{c:08x}_data" {{\n\ttuples "{PREFIX}.c{c:08x}_tuples"\n}}\n')

    blobs = {RX_HEAD: [(CFG_GRAPH_OPEN, v.graph_open_params("rx")),
                       (CFG_PERSISTENT, b"".join(v.cal_p["rx"])),
                       (CFG_SET, v.set_params("rx")),
                       (CFG_SET_LATE, v.set_late_params()),
                       (CFG_PLAYBACK_LINKS, v.playback_links())],
             TX_TAIL: [(CFG_GRAPH_OPEN, v.graph_open_params("tx")),
                       (CFG_PERSISTENT, b"".join(v.cal_p["tx"])),
                       (CFG_SET, v.set_params("tx"))]}
    for iid, m in sorted(v.mods.items()):
        links = [c for c in v.conns if c[0] == iid]
        if len(links) > 8:
            sys.exit(f"module {iid:#x}: {len(links)} links, max 8")
        t = [f'\t\tAR_TKN_U32_MODULE_INSTANCE_ID "0x{iid:x}"',
             f'\t\tAR_TKN_U32_MODULE_ID "0x{m["id"]:08x}"',
             f'\t\tAR_TKN_U32_MODULE_MAX_IP_PORTS "{m["ports"][0]}"',
             f'\t\tAR_TKN_U32_MODULE_MAX_OP_PORTS "{m["ports"][1]}"',
             f'\t\tAR_TKN_U32_MODULE_SRC_INSTANCE_ID "0x{iid:x}"']
        for n, (_, sp, dst, dp) in enumerate(links):
            sfx = "" if n == 0 else str(n)
            t += [f'\t\tAR_TKN_U32_MODULE_SRC_OP_PORT_ID{sfx} "{sp}"',
                  f'\t\tAR_TKN_U32_MODULE_DST_IN_PORT_ID{sfx} "{dp}"',
                  f'\t\tAR_TKN_U32_MODULE_DST_INSTANCE_ID{sfx} "0x{dst:x}"']
        w(f'SectionVendorTuples."{name(iid)}_tuples" {{\n\ttokens "{PREFIX}_tokens"\n'
          f'\ttuples."word.u32_data" {{\n' + "\n".join(t) + "\n\t}\n}\n"
          f'SectionData."{name(iid)}_data" {{\n\ttuples "{name(iid)}_tuples"\n}}\n')
        data = [f"{PREFIX}.sg{m['sg']:08x}_data", f"{PREFIX}.c{m['cont']:08x}_data",
                f"{name(iid)}_data"]
        for n, (kind, payload) in enumerate(blobs.get(iid, [])):
            if payload:
                # alsa-lib >= 1.2.16 takes at most 16 KiB per bytes list;
                # alsatplg concatenates a widget's data sections in order
                arr = cfg_array(kind, payload)
                for k in range(0, len(arr), DATA_CHUNK):
                    sfx = "" if k == 0 else f"_{k // DATA_CHUNK}"
                    w(f'SectionData."{name(iid)}_cfg{n}{sfx}" {{\n'
                      f'\tbytes "{hexbytes(arr[k:k + DATA_CHUNK])}"\n}}\n')
                    data.append(f"{name(iid)}_cfg{n}{sfx}")
        if iid == RX_HEAD:
            kind = f'\ttype "aif_in"\n\tstream_name "{FE_NAME} Playback"\n'
        elif iid == TX_TAIL:
            kind = f'\ttype "aif_out"\n\tstream_name "{FE_TX_NAME} Capture"\n'
        else:
            kind = '\ttype "buffer"\n'
        fe = FE if v.dir_of(iid) == "rx" else FE_TX
        w(f'SectionWidget."{name(iid)}" {{\n\tindex "{fe}"\n{kind}\tno_pm "true"\n\tsubseq "10"\n'
          f'\tdata [\n' + "\n".join(f'\t\t"{d}"' for d in data) + "\n\t]\n}\n")

    # DAPM paths along the data connections, plus the device mixers
    for dr, fe in (("rx", FE), ("tx", FE_TX)):
        lines = sorted(set(f'"{name(c[2])}, , {name(c[0])}"' for c in v.conns
                           if v.dir_of(c[0]) == dr))
        if dr == "rx":
            lines.append(f'"{SPEAKER_MIXER}, {FE_NAME}, {name(RX_TAIL)}"')
        else:
            lines.append(f'"{name(TX_HEAD)}, , {FE_TX_NAME} Mixer"')
            lines.append(f'"{FE_TX_NAME} Mixer, {MIC_DEVICE}, {MIC_DEVICE_WIDGET}"')
        w(f'SectionGraph."{PREFIX} {dr} Graph" {{\n\tindex "{fe}"\n\tlines [\n' +
          "\n".join(f"\t\t{l}" for l in lines) + "\n\t]\n}\n")

    # mixer control for the speaker device mixer, capture mixer
    w(f'SectionControlMixer."{FE_NAME}" {{\n\treg "-1"\n\tindex "{FE}"\n\tmax "1"\n\tinvert "false"\n'
      f'\tchannel."fl" {{\n\t\treg "-1"\n\t\tmax "1"\n\t}}\n'
      f'\tops."ctl" {{\n\t\tget "256"\n\t\tput "256"\n\t\tinfo "1"\n\t}}\n'
      f'\tdata [\n\t\t"{PREFIX}.sg{v.mods[RX_TAIL]["sg"]:08x}_data"\n\t]\n}}\n')
    w(f'SectionWidget."{FE_TX_NAME} Mixer" {{\n\treg "-1"\n\tindex "{FE_TX}"\n\ttype "mixer"\n'
      f'\tmixer [\n\t\t"{MIC_DEVICE}"\n\t]\n'
      f'\tdata [\n\t\t"{PREFIX}.sg{v.mods[TX_HEAD]["sg"]:08x}_data"\n\t]\n}}\n')

    w(f'SectionPCMCapabilities."{FE_NAME} Playback" {{\n\tformats "S16_LE"\n\trate_min "8000"\n'
      f'\trate_max "48000"\n\tchannels_min "1"\n\tchannels_max "2"\n}}\n'
      f'SectionPCMCapabilities."{FE_TX_NAME} Capture" {{\n\tformats "S16_LE"\n\trate_min "8000"\n'
      f'\trate_max "48000"\n\tchannels_min "1"\n\tchannels_max "2"\n}}\n'
      f'SectionPCM."{FE_NAME} Voice" {{\n\tindex "{FE}"\n\tid "{FE}"\n'
      f'\tdai."{FE_NAME} Voice" {{\n\t\tid "{FE}"\n\t}}\n'
      f'\tpcm."playback" {{\n\t\tcapabilities "{FE_NAME} Playback"\n\t}}\n}}\n'
      f'SectionPCM."{FE_TX_NAME} Voice" {{\n\tindex "{FE_TX}"\n\tid "{FE_TX}"\n'
      f'\tdai."{FE_TX_NAME} Voice" {{\n\t\tid "{FE_TX}"\n\t}}\n'
      f'\tpcm."capture" {{\n\t\tcapabilities "{FE_TX_NAME} Capture"\n\t}}\n}}\n')
    return "\n".join(o)


def main():
    global VSID
    if "--loopback" in sys.argv:
        VSID = VSID_LOOPBACK
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    v = Voice(args[0], args[1], devpp="--no-devpp" not in sys.argv)
    sys.stderr.write(f"voice: {len(v.sgs)} subgraphs, {len(v.conts)} containers, "
                     f"{len(v.mods)} modules, {len(v.conns)} connections, "
                     f"control links rx {len(v.ctrl_of('rx'))} tx {len(v.ctrl_of('tx'))} "
                     f"(+{len(v.ctrl_play)} at playback), persistent cal "
                     f"rx {sum(map(len, v.cal_p['rx']))} B tx {sum(map(len, v.cal_p['tx']))} B\n")
    sys.stdout.write(emit(v))


if __name__ == "__main__":
    main()
