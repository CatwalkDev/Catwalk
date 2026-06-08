#!/usr/bin/env python3
"""Fetch a real mechanical-keyboard recording from Wikimedia Commons and slice it
into individual key taps for Catwalk's 'Click' sound. Writes Sounds/click_*.wav and
appends attribution to Sounds/CREDITS.txt. Requires ffmpeg/ffprobe + network."""
import os, re, json, subprocess, urllib.parse, urllib.request

UA = "CatwalkApp/1.0 (open-source menu-bar utility)"
HERE = os.path.dirname(os.path.abspath(__file__))
SND = os.path.join(HERE, 'Sounds'); TMP = '/tmp/catwalk_clicks'
os.makedirs(SND, exist_ok=True); os.makedirs(TMP, exist_ok=True)
N_TAPS = 8

def api(params):
    params['format'] = 'json'
    req = urllib.request.Request("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params),
                                 headers={'User-Agent': UA})
    return json.load(urllib.request.urlopen(req, timeout=40))

def find():
    for t in ["mechanical keyboard", "keyboard typing", "typewriter", "computer keyboard", "key press"]:
        d = api(dict(action='query', generator='search', gsrsearch=t, gsrnamespace=6, gsrlimit=30,
                     prop='imageinfo', iiprop='url|mime|size|extmetadata'))
        for p in (d.get('query', {}).get('pages', {}) or {}).values():
            ii = (p.get('imageinfo') or [{}])[0]
            if not ii.get('mime', '').startswith('audio'): continue
            title = p.get('title', '').replace('File:', '')
            if not any(k in title.lower() for k in ('keyboard', 'typewriter', 'typing', 'keychron', 'schreibmaschine')):
                continue
            ex = ii.get('extmetadata', {})
            return dict(title=title, url=ii.get('url', ''),
                        lic=ex.get('LicenseShortName', {}).get('value', ''),
                        art=re.sub('<[^>]+>', '', ex.get('Artist', {}).get('value', '') or '').strip())
    return None

def download(url, dst):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=240) as r, open(dst, 'wb') as f:
        f.write(r.read())

def dur(p):
    r = subprocess.run(['ffprobe', '-v', 'quiet', '-show_entries', 'format=duration', '-of', 'csv=p=0', p],
                       capture_output=True, text=True)
    try: return float(r.stdout.strip())
    except: return 0.0

def taps(path, noise='-26dB', gap=0.03, pad=0.012):
    out = subprocess.run(['ffmpeg', '-hide_banner', '-i', path, '-af',
                          f'silencedetect=noise={noise}:d={gap}', '-f', 'null', '-'],
                         stderr=subprocess.PIPE, text=True).stderr
    starts = [float(x) for x in re.findall(r'silence_start: ([0-9.]+)', out)]
    ends = [float(x) for x in re.findall(r'silence_end: ([0-9.]+)', out)]
    D = dur(path); sil = []
    for i, s in enumerate(starts):
        sil.append((s, ends[i] if i < len(ends) else D))
    sil.sort(); voiced = []; cur = 0.0
    for s, e in sil:
        if s > cur: voiced.append((cur, s))
        cur = max(cur, e)
    if cur < D: voiced.append((cur, D))
    return [(max(0, a - pad), min(D, b + pad)) for a, b in voiced if 0.02 <= b - a <= 0.35]

c = find()
if not c:
    print("No keyboard recording found on Commons."); raise SystemExit(1)
print("source:", c['title'], "-", c['lic'])
ext = os.path.splitext(urllib.parse.urlparse(c['url']).path)[1] or '.wav'
raw = os.path.join(TMP, 'kbd' + ext)
download(c['url'], raw)

for f in os.listdir(SND):
    if f.lower().startswith('click') and f.lower().endswith('.wav'):
        os.remove(os.path.join(SND, f))

segs = taps(raw)[2:]                       # skip the first couple (often handling noise)
pick = segs[::max(1, len(segs) // N_TAPS)][:N_TAPS] if segs else []
idx = 1
for a, b in pick:
    dst = os.path.join(SND, f'click_{idx}.wav')
    af = "afade=t=in:st=0:d=0.003,loudnorm=I=-18:TP=-2:LRA=11"
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-ss', f'{a:.3f}', '-i', raw,
                    '-t', f'{min(0.22, b - a):.3f}', '-ac', '1', '-ar', '44100', '-af', af, dst])
    if os.path.exists(dst) and os.path.getsize(dst) > 1500:
        print(f"  click_{idx}.wav  {dur(dst):.3f}s"); idx += 1
    elif os.path.exists(dst):
        os.remove(dst)

cp = os.path.join(SND, 'CREDITS.txt')
prev = open(cp).read() if os.path.exists(cp) else ""
with open(cp, 'w') as f:
    f.write(prev.rstrip() + f"\n\nKeyboard taps:\n- {c['title']}, {c['lic']}"
            + (f", {c['art']}" if c['art'] else "") + "\n")
print(f"\nTotal key taps: {idx - 1}")
