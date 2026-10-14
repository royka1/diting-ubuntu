import struct, sys, glob, os
names = {}
for l in open(os.environ.get('APM_IDS', 'ids.txt')):
    v, n = l.split()
    names.setdefault(int(v, 16), []).append(n)
def nm(v, pref=None):
    c = names.get(v, [])
    if pref: c = [x for x in c if pref in x] or c
    return f"{v:#010x}" + (f"({c[0]})" if c else "")
def props(b, o, n):
    out = []
    for _ in range(n):
        pid, sz = struct.unpack_from('<II', b, o); o += 8
        pl = b[o:o+sz]; o += sz
        vals = struct.unpack_from(f'<{sz//4}I', pl) if sz % 4 == 0 else pl
        out.append(f"{nm(pid)}={[hex(x) for x in vals] if isinstance(vals, tuple) else vals.hex()}")
    return o, out
def decode(path):
    b = open(path, 'rb').read(); o = 0
    print(f"== {os.path.basename(path)} ({len(b)} B)")
    while o + 16 <= len(b):
        iid, pid, sz, err = struct.unpack_from('<IIII', b, o); o += 16
        p = b[o:o+sz]; o += (sz + 7) & ~7
        if pid == 0x08001001:
            n, = struct.unpack_from('<I', p); q = 4
            for _ in range(n):
                sg, np_ = struct.unpack_from('<II', p, q); q += 8
                q, pr = props(p, q, np_); print(f"  SUBGRAPH {sg:#x}: {', '.join(pr)}")
        elif pid == 0x08001000:
            n, = struct.unpack_from('<I', p); q = 4
            for _ in range(n):
                c, np_ = struct.unpack_from('<II', p, q); q += 8
                q, pr = props(p, q, np_); print(f"  CONTAINER {c:#x}: {', '.join(pr)}")
        elif pid == 0x08001002:
            n, = struct.unpack_from('<I', p); q = 4
            for _ in range(n):
                sg, c, nmod = struct.unpack_from('<III', p, q); q += 12
                for _ in range(nmod):
                    mid, miid = struct.unpack_from('<II', p, q); q += 8
                    print(f"  MODULE sg {sg:#x} cont {c:#x} iid {miid:#x} {nm(mid, 'MODULE_ID')}")
        elif pid == 0x08001003:
            n, = struct.unpack_from('<I', p); q = 4
            for _ in range(n):
                miid, np_ = struct.unpack_from('<II', p, q); q += 8
                q, pr = props(p, q, np_); print(f"  MODPROP iid {miid:#x}: {', '.join(pr)}")
        elif pid == 0x08001004:
            n, = struct.unpack_from('<I', p); q = 4
            for _ in range(n):
                a = struct.unpack_from('<IIII', p, q); q += 16
                print(f"  CONN {a[0]:#x}:{a[1]:#x} -> {a[2]:#x}:{a[3]:#x}")
        elif pid == 0x08001061:
            n, = struct.unpack_from('<I', p); q = 4
            for _ in range(n):
                a = struct.unpack_from('<IIIII', p, q); q += 20
                q, pr = props(p, q, a[4]); print(f"  CTRL_LINK {a[0]:#x}:{a[1]:#x} <-> {a[2]:#x}:{a[3]:#x} {', '.join(pr)}")
        else:
            w = struct.unpack_from(f'<{sz//4}I', p) if sz % 4 == 0 else ()
            print(f"  PARAM iid {iid:#x} {nm(pid)} [{sz}] {' '.join(hex(x) for x in w[:24])}")
for f in sys.argv[1:]:
    decode(f)
