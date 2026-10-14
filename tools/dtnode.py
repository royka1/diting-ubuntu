#!/usr/bin/env python3
"""Print a node from a dtc-decompiled DTS, annotating phandle references
with the referenced node path. Usage: dtnode.py file.dts <node-regex>"""
import re, sys

def parse(path):
    stack, nodes, cur = [], {}, None
    for line in open(path):
        s = line.strip()
        m = re.match(r'([^\s{]+) \{$', s)
        if m:
            stack.append(m.group(1)); cur = '/'.join(stack[1:]) or '/'
            nodes.setdefault(cur, []); continue
        if s == '};':
            stack.pop(); cur = '/'.join(stack[1:]) or '/'; continue
        if cur is not None and s:
            nodes[cur].append(s)
    ph = {}
    for n, props in nodes.items():
        for p in props:
            m = re.match(r'phandle = <(0x[0-9a-f]+)>;', p)
            if m: ph[int(m.group(1), 16)] = n
    return nodes, ph

nodes, ph = parse(sys.argv[1])
pat = re.compile(sys.argv[2])
for n, props in nodes.items():
    if pat.search(n):
        print(f"== {n}")
        for p in props:
            note = ''
            if re.search(r'(supply|gpios?|-gpio|phys|pinctrl-\d|clocks|resets|interconnects|power-domains|repeater|iommus) = <', p):
                refs = [int(x, 16) for x in re.findall(r'0x[0-9a-f]+', p)]
                hits = sorted({ph[r] for r in refs if r in ph})
                if hits: note = '   # -> ' + ', '.join(h.split('/')[-1] for h in hits)
            print('   ', p + note)
