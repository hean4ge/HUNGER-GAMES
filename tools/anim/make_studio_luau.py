"""
make_studio_luau.py - pastes a <Name>.studio.json into studio_build_kfs.luau.

    python make_studio_luau.py <Name>.studio.json [label] [folder]  ->  <Name>.build.luau next to the JSON

The text of <Name>.build.luau is what goes into the Studio tool's execute_luau (Edit datamodel).
label  = the agent's name in the shared-Studio lock (default "anim")
folder = the ServerStorage folder that receives the KeyframeSequence (default "AnimSource")
"""
import os
import sys

src = sys.argv[1]
label = sys.argv[2] if len(sys.argv) > 2 else "anim"
folder = sys.argv[3] if len(sys.argv) > 3 else "AnimSource"
here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "studio_build_kfs.luau"), "r", encoding="utf-8") as f:
    template = f.read()
with open(src, "r", encoding="utf-8") as f:
    payload = f.read().strip()
assert "]==]" not in payload
out = template.replace("__JSON__", payload).replace("__LABEL__", label).replace("__FOLDER__", folder)
dst = src.replace(".studio.json", ".build.luau")
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    f.write(out)
print("wrote %s (%d bytes, payload %d bytes)" % (dst, len(out), len(payload)))
