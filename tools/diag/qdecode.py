#!/usr/bin/python3 -I
"""decode 'Q hash ssid line args...' lines of adsp_diag with a QShrink qdb text"""
import re, sys
db = {}
for l in open(sys.argv[1], errors="replace"):
    p = l.rstrip("\n").split(":", 5)
    if len(p) == 6 and p[0].isdigit():
        db[int(p[0])] = (p[4], p[3], p[5])
for l in open(sys.argv[2], errors="replace"):
    if not l.startswith("Q "):
        print(l, end="")
        continue
    f = l.split()
    h = int(f[1]); args = [int(a, 16) for a in f[4:]]
    if h not in db:
        print(f"?{h} ssid={f[2]} line={f[3]} {f[4:]}")
        continue
    file, line, fmt = db[h]
    fmt2 = re.sub(r"%(l|ll|h)?([dxXuips])", lambda m: "%" + ("s" if m.group(2) == "s" else ("x" if m.group(2) in "xXp" else "d")), fmt)
    fmt2 = fmt2.replace("%s", "%r")
    try:
        txt = fmt2 % tuple(args[:fmt2.count("%") - fmt2.count("%%") * 2])
    except Exception:
        txt = fmt + " " + str([hex(a) for a in args])
    print(f"{file}:{line} {txt}")
