#!/usr/bin/python3 -I
"""Split adsp_diag --log-dump output (DLS PCM log packets of the AudioReach
data logging modules) into one WAV per log code and tap:
  dls2wav.py logs.bin OUTDIR"""
import os, struct, sys, wave, collections

d = open(sys.argv[1], "rb").read()
out = sys.argv[2]
os.makedirs(out, exist_ok=True)
streams = collections.OrderedDict()
o = 0
while o + 2 <= len(d):
    n = struct.unpack_from("<H", d, o)[0]
    p = d[o + 2:o + 2 + n]
    o += 2 + n
    if len(p) < 76:
        continue
    code = struct.unpack_from("<H", p, 6)[0]
    # after the DIAG and log headers (16 bytes): header len/version,
    # session, segment number, data size, ..., tap id, rate, bits/channels
    w = struct.unpack_from("<15I", p, 16)
    size, tap, rate = w[3], w[11] & 0xFFFF, w[12]
    ch, bits = w[13] & 0xFFFF, w[13] >> 16
    if not size or size > len(p) - 76 or rate not in (8000, 16000, 32000, 48000) \
            or not 1 <= ch <= 8 or bits not in (16, 24, 32):
        continue
    key = (code, tap, w[1], rate, ch, bits)
    data = p[len(p) - size:]
    interleaved = (w[13] >> 24) & 0xFF
    if ch > 1 and not interleaved:
        # planar segment: all samples of channel 0, then channel 1, ...
        bps = bits // 8
        n = size // (ch * bps)
        planes = [data[c * n * bps:(c + 1) * n * bps] for c in range(ch)]
        data = b"".join(b"".join(pl[i * bps:(i + 1) * bps] for pl in planes) for i in range(n))
    streams.setdefault(key, bytearray()).extend(data)
for (code, tap, sess, rate, ch, bits), pcm in streams.items():
    name = f"{out}/{code:04x}_tap{tap:x}_s{sess:08x}_{rate}_{ch}ch_{bits}b.wav"
    w = wave.open(name, "wb")
    w.setnchannels(ch); w.setsampwidth(bits // 8); w.setframerate(rate)
    w.writeframes(bytes(pcm[:len(pcm) - len(pcm) % (ch * bits // 8)]))
    w.close()
    print(f"{name}: {len(pcm) / (rate * ch * bits / 8):.2f} s")
