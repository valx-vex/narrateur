#!/usr/bin/env python3
"""Synthetic data only. No call/import of the real engine or any TTS backend."""
from pathlib import Path
import json, sys
root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)
(root/'.narrateur-smoke').write_text('synthetic fixture\n')
titles = ['The room before dawn', 'A map of quiet places', 'The listening room', 'Small departures', 'A voice in the archive', 'Between the lines', 'The long way home', 'What the night remembers', 'A table by the window', 'The next chapter']
(root/'story.md').write_text('# The Quiet Atlas — Fixture\n\n'+'\n'.join(f'# Chapter {n} — {title}\nA short synthetic sentence.\n' for n,title in enumerate(titles,1)))
(root/'book.toml').write_text('title = "The Quiet Atlas — Fixture"\nauthor = "A fixture author"\nlanguage = "English"\nsource = "story.md"\nchapter_heading = "# Chapter "\n\n[voice]\nmodel = "customvoice"\nvoice = "Ryan"\n')
voice = root/'voices'/'house'; voice.mkdir(parents=True, exist_ok=True)
(voice/'voice.toml').write_text('name="House narrator"\nowner="fixture"\nlanguage="English"\nmodel="customvoice"\nvoice="Ryan"\n')
engine = root/'bin'/'book-audio'; engine.parent.mkdir(exist_ok=True)
engine.write_text('''#!/usr/bin/python3
import math, os, pathlib, re, struct, subprocess, sys, wave
assert len(sys.argv) == 3 and sys.argv[1] == "all", "unexpected arguments"
root = pathlib.Path(sys.argv[2]).resolve().parent
assert (root/".narrateur-smoke").is_file(), "fixture marker required"
assert "BOOK_AUDIO_BACKEND" not in os.environ, "backend leaked"
chapters = root/"audio"/"chapters"; chapters.mkdir(parents=True, exist_ok=True)
cache = root/".book-audio"/"cache"; cache.mkdir(parents=True, exist_ok=True)
for line in (root/"story.md").read_text().splitlines():
    match = re.match(r"# Chapter (\\d+) — (.*)", line)
    if not match: continue
    number, title = int(match[1]), match[2]
    slug = f"{number:02d}_" + re.sub("[^a-z0-9]+", "-", title.lower()).strip("-")
    (chapters/(slug+".md")).write_text(f"# Chapter {number} — {title}\\n- duration: 1.0 s\\n- retries: 0\\n")
for n in range(12): (cache/f"{n:064x}.wav").write_bytes(b"fixture")
wav = root/"fixture.wav"
with wave.open(str(wav), "wb") as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(24000)
    f.writeframes(b"".join(struct.pack("<h", int(500*math.sin(i*2*math.pi*220/24000))) for i in range(24000)))
out = root/"audio"/"The Quiet Atlas — Fixture.m4b"
subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", "32k", str(out)], check=True)
(root/"audio"/"REPORT.md").write_text("# Synthetic smoke result\\n10 reports; one-second test tone, no narration.\\n")
print(out)
''')
engine.chmod(0o755)
print(root)
