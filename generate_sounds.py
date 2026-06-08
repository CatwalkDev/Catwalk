#!/usr/bin/env python3
"""Generates the procedural Purr and Hiss loops into ./Sounds (pure stdlib, 16-bit mono
WAVs). Bloop uses a macOS system sound; the Keyboard sound comes from fetch_clicks.py.
Drop in your own purr.wav / hiss.wav to replace these."""
import wave, struct, math, random, os, glob

SR = 44100
random.seed(20240607)

def norm(s, peak=0.82):
    p = max(1e-9, max(abs(x) for x in s))
    g = peak / p
    return [x * g for x in s]

def write_wav(path, s):
    s = norm(s)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x)) * 32767)) for x in s))

def lowpass(x, fc):
    rc = 1.0 / (2 * math.pi * fc); dt = 1.0 / SR; a = dt / (rc + dt)
    y = 0.0; out = []
    for v in x:
        y += a * (v - y); out.append(y)
    return out

def highpass(x, fc):
    rc = 1.0 / (2 * math.pi * fc); dt = 1.0 / SR; a = rc / (rc + dt)
    px = py = 0.0; out = []
    for v in x:
        py = a * (py + v - px); out.append(py); px = v
    return out

def white(n):
    return [random.uniform(-1, 1) for _ in range(n)]

def make_purr():
    """Low brown-noise rumble amplitude-modulated ~26 Hz, crossfaded into a seamless loop."""
    L, cf = 3.0, 0.3
    n = int((L + cf) * SR)
    b = [0.0] * n; v = 0.0
    for i in range(n):
        v = v * 0.997 + random.uniform(-1, 1) * 0.05
        b[i] = v
    b = lowpass(b, 450)
    for i in range(n):
        b[i] += 0.25 * math.sin(2 * math.pi * 46 * (i / SR))
    ph = 0.0; rate = 26.0; out = [0.0] * n
    for i in range(n):
        rate += random.uniform(-0.02, 0.02); rate = max(23, min(29, rate))
        ph += 2 * math.pi * rate / SR
        p = (0.5 + 0.5 * math.sin(ph)); p *= p
        out[i] = b[i] * (0.32 + 0.68 * p)
    Ls, cfs = int(L * SR), int(cf * SR)
    final = out[:Ls]
    for i in range(cfs):
        t = i / cfs
        final[i] = out[i] * t + out[Ls + i] * (1 - t)
    return final

def make_hiss_loop():
    """Sustained, seamless-looping hiss: a sibilant band + an airy body band with a
    breathy flutter, crossfaded end-to-start so it loops smoothly while keys are held."""
    Ls, cfs = int(2.0 * SR), int(0.3 * SR)            # body length + crossfade length
    n = Ls + cfs                                      # buffer == Ls+cfs (dodges fp rounding)
    sib  = lowpass(highpass(white(n), 3200), 8500)    # sibilance
    body = lowpass(highpass(white(n), 700), 2600)     # airy body
    mix = [0.85 * sib[i] + 0.5 * body[i] for i in range(n)]
    # breathy flutter: a slow smoothed-random gain wobble (the "spit" texture)
    flut = [0.0] * n; v = 0.0
    for i in range(n):
        v += (random.uniform(-1, 1) - v) * 0.02
        flut[i] = v
    fp = max(1e-9, max(abs(x) for x in flut))
    flut = [0.72 + 0.28 * (x / fp) for x in flut]
    out = [mix[i] * flut[i] for i in range(n)]        # constant level, no attack/decay
    final = out[:Ls]
    for i in range(cfs):                              # crossfade the tail into the head
        t = i / cfs
        final[i] = out[i] * t + out[Ls + i] * (1 - t)
    return final

d = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Sounds')
os.makedirs(d, exist_ok=True)

# Old numbered hiss pool is replaced by a single seamless loop; clear it.
# (Leave click_*.wav alone; those are the fetched keyboard taps.)
for stale in glob.glob(os.path.join(d, 'hiss_*.wav')):
    os.remove(stale)

write_wav(os.path.join(d, 'purr.wav'), make_purr())
write_wav(os.path.join(d, 'hiss.wav'), make_hiss_loop())
print("wrote:", sorted(f for f in os.listdir(d) if f.endswith('.wav')))
