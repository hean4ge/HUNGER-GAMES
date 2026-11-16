"""studio_sync - exact two-way sync between the repo's src/ and the place open in Roblox Studio.

See README.md beside this file. The Studio side is ServerStorage.Dev.StudioSync (src/ServerStorage/Dev/StudioSync.lua).

  python tools/studio_sync/sync.py status
  python tools/studio_sync/sync.py push [--force] <file or Studio path> ...     (or: push --changed)
  python tools/studio_sync/sync.py check <file or Studio path> ...
  python tools/studio_sync/sync.py confirm <pack>
  python tools/studio_sync/sync.py pull <runId> [--write] [--state-only]
  python tools/studio_sync/sync.py blob <packName> <name>=<file> ...
  python tools/studio_sync/sync.py bootstrap
  python tools/studio_sync/sync.py clean
"""
import base64
import glob
import io
import json
import os
import random
import subprocess
import sys
import time
from xml.sax.saxutils import escape

BS = chr(92)
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
STATE_DIR = os.path.join(REPO, ".studio_sync")
STATE = os.path.join(STATE_DIR, "state.json")
LOCK = os.path.join(STATE_DIR, "lock")
CHUNK = 150000  # characters of base64 per StringValue
EXTS = ((".client.lua", "LocalScript"), (".server.lua", "Script"), (".lua", "ModuleScript"))
HEADER = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
)


def lp(p):
    """Windows long-path form of p."""
    return BS + BS + "?" + BS + os.path.abspath(p).replace("/", BS)


def read_bytes(p):
    with open(lp(p), "rb") as fh:
        return fh.read()


def write_bytes(p, data):
    d = os.path.dirname(os.path.abspath(p))
    todo = []
    while not os.path.isdir(lp(d)) and os.path.dirname(d) != d:
        todo.append(d)
        d = os.path.dirname(d)
    for x in reversed(todo):
        os.mkdir(lp(x))
    with open(lp(p), "wb") as fh:
        fh.write(data)


def fnv(data):
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return "%08x" % h


def studio_dir():
    """Studio's content/ls_import folder: the running Studio's install, else the newest installed version."""
    cands = []
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Select-Object -First 1).Path"],
            capture_output=True, text=True, timeout=40).stdout.strip()
        if out and os.path.isfile(out):
            cands.append(os.path.dirname(out))
    except Exception:
        pass
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "Versions")
    exes = glob.glob(os.path.join(base, "*", "RobloxStudioBeta.exe"))
    cands += [os.path.dirname(p) for p in sorted(exes, key=os.path.getmtime, reverse=True)]
    for c in cands:
        content = os.path.join(c, "content")
        if os.path.isdir(content):
            d = os.path.join(content, "ls_import")
            os.makedirs(d, exist_ok=True)
            return d
    sys.exit("Roblox Studio's content folder was not found")


def newest_log_with(text):
    logs = glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""), "Roblox", "logs", "*Studio*last.log"))
    for cand in sorted(logs, key=os.path.getmtime, reverse=True)[:6]:
        with io.open(cand, encoding="utf-8", errors="replace") as fh:
            if text in fh.read():
                return cand
    return None


def load_manifest():
    return json.loads(read_bytes(os.path.join(REPO, "src", "manifest.json")).decode("utf-8"))


def studio_path_for(rel):
    """(Studio path, class) for a file under src/, by the Rojo rules in src/README.md."""
    parts = rel.replace(BS, "/").split("/")
    if parts[0] != "src" or len(parts) < 3:
        sys.exit("not under src/<Service>/: " + rel)
    fname = parts[-1]
    for ext, cls in EXTS:
        if fname.endswith(ext):
            stem = fname[: -len(ext)]
            break
    else:
        sys.exit("not a script file (.lua, .client.lua, .server.lua): " + rel)
    if stem == "init":
        return ".".join(parts[1:-1]), cls
    return ".".join(parts[1:-1] + [stem]), cls


def all_scripts():
    """Every script file under src/: {studioPath: {file, cls, runContext}} (the manifest first, then new files)."""
    m = load_manifest()
    out = {}
    for s in m["scripts"]:
        out[s["studioPath"]] = {"file": s["file"], "cls": s["class"], "runContext": s.get("runContext")}
    tracked = {v["file"] for v in out.values()}
    for root, _dirs, files in os.walk(os.path.join(REPO, "src")):
        for f in files:
            if not f.endswith(".lua"):
                continue
            rel = os.path.relpath(os.path.join(root, f), REPO).replace(BS, "/")
            if rel in tracked:
                continue
            sp, cls = studio_path_for(rel)
            out[sp] = {"file": rel, "cls": cls, "runContext": "Legacy" if cls == "Script" else None}
    return out


class Locked:
    def __enter__(self):
        os.makedirs(STATE_DIR, exist_ok=True)
        for _ in range(600):
            try:
                os.mkdir(LOCK)
                return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(LOCK) > 120:
                        os.rmdir(LOCK)
                        continue
                except OSError:
                    pass
                time.sleep(0.1)
        sys.exit("could not take the state lock (" + LOCK + ")")

    def __exit__(self, *a):
        try:
            os.rmdir(LOCK)
        except OSError:
            pass


def load_state():
    if os.path.isfile(STATE):
        return json.loads(read_bytes(STATE).decode("utf-8"))
    m = load_manifest()
    return {s["studioPath"]: {"fnv": s["fnv1a"], "bytes": s["bytes"]} for s in m["scripts"]}


def save_state(state):
    os.makedirs(STATE_DIR, exist_ok=True)
    write_bytes(STATE, (json.dumps(state, indent=1, sort_keys=True) + "\n").encode("utf-8"))


def pack_name():
    return "p%s_%04x" % (time.strftime("%H%M%S"), random.randrange(65536))


def write_pack(name, entries, blobs):
    """entries: index dicts without chunk counts; blobs: the bytes for each entry, same order."""
    items = []
    for e, data in zip(entries, blobs):
        b64 = base64.b64encode(data).decode("ascii")
        chunks = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)]
        e["chunks"] = len(chunks)
        for k, c in enumerate(chunks, 1):
            items.append(("E%d_%d" % (e["i"], k), c))
    index = json.dumps({"pack": name, "entries": entries}, ensure_ascii=True)
    out = [HEADER, '<Item class="Folder" referent="R0"><Properties><string name="Name">LSPack</string></Properties>']
    ref = 1
    for nm, value in [("Index", escape(index))] + items:
        out.append('<Item class="StringValue" referent="R%d"><Properties><string name="Name">%s</string>'
                   '<string name="Value">%s</string></Properties></Item>' % (ref, nm, value))
        ref += 1
    out.append("</Item></roblox>")
    path = os.path.join(studio_dir(), name + ".rbxmx")
    write_bytes(path, "\n".join(out).encode("utf-8"))
    return path


def resolve_targets(args, scripts):
    by_file = {v["file"]: k for k, v in scripts.items()}
    picked = []
    for a in args:
        rel = a.replace(BS, "/")
        if os.path.isabs(a):
            rel = os.path.relpath(a, REPO).replace(BS, "/")
        if rel in by_file:
            picked.append(by_file[rel])
        elif a in scripts:
            picked.append(a)
        elif os.path.isdir(os.path.join(REPO, rel)):
            pre = rel.rstrip("/") + "/"
            picked += [k for k, v in scripts.items() if v["file"].startswith(pre)]
        else:
            sys.exit("no script matches: " + a)
    return sorted(set(picked))


def cmd_status(_args):
    scripts = all_scripts()
    state = load_state()
    rows = []
    for sp, info in sorted(scripts.items()):
        data = read_bytes(os.path.join(REPO, info["file"]))
        st = state.get(sp)
        if st is None:
            rows.append(("new", sp, len(data)))
        elif st["fnv"] != fnv(data) or st["bytes"] != len(data):
            rows.append(("changed", sp, len(data)))
    print("%d script files; %d differ from what Studio last had:" % (len(scripts), len(rows)))
    for kind, sp, n in rows:
        print("  %-8s %-90s %7d" % (kind, sp, n))


def cmd_push(args):
    force = "--force" in args
    changed = "--changed" in args
    args = [a for a in args if not a.startswith("--")]
    scripts = all_scripts()
    with Locked():
        state = load_state()
    if changed:
        targets = []
        for sp, info in scripts.items():
            data = read_bytes(os.path.join(REPO, info["file"]))
            st = state.get(sp)
            if st is None or st["fnv"] != fnv(data) or st["bytes"] != len(data):
                targets.append(sp)
        targets.sort()
    else:
        targets = resolve_targets(args, scripts)
    if not targets:
        print("nothing to push")
        return
    targets.sort(key=lambda sp: (sp.count("."), sp))  # parents before children
    entries, blobs = [], []
    for i, sp in enumerate(targets, 1):
        info = scripts[sp]
        data = read_bytes(os.path.join(REPO, info["file"]))
        if b"\r" in data:
            sys.exit(info["file"] + " has CR line endings; Studio sources use LF only")
        if data.startswith(b"\xef\xbb\xbf"):
            sys.exit(info["file"] + " starts with a BOM")
        if len(data) > 199000:
            sys.exit("%s is %d bytes; a script Source is capped at 200,000 characters" % (info["file"], len(data)))
        before = state.get(sp, {}).get("fnv")
        entries.append({"i": i, "kind": "script", "path": sp, "class": info["cls"], "runContext": info["runContext"],
                        "bytes": len(data), "fnv": fnv(data), "before": before})
        blobs.append(data)
    name = pack_name()
    path = write_pack(name, entries, blobs)
    print("pack %s: %d scripts -> %s" % (name, len(entries), path))
    for e in entries:
        print("  %-90s %7d %s" % (e["path"], e["bytes"], "(new to Studio)" if e["before"] is None else ""))
    opts = ", { force = true }" if force else ""
    print("\nNow run in Studio (Edit mode, execute_luau):")
    print('  return require(game.ServerStorage.Dev.StudioSync:Clone()).apply("%s"%s)' % (name, opts))
    print("then:  python tools/studio_sync/sync.py confirm %s" % name)


def cmd_check(args):
    """Compile-check files in Studio without installing them (works for files that are not ready to push)."""
    scripts = all_scripts()
    targets = resolve_targets([a for a in args if not a.startswith("--")], scripts)
    entries, blobs = [], []
    for i, sp in enumerate(targets, 1):
        info = scripts[sp]
        data = read_bytes(os.path.join(REPO, info["file"]))
        entries.append({"i": i, "kind": "script", "path": sp, "class": info["cls"], "runContext": info["runContext"],
                        "bytes": len(data), "fnv": fnv(data), "before": None})
        blobs.append(data)
    name = "c" + pack_name()[1:]
    write_pack(name, entries, blobs)
    print("check pack %s: %d scripts" % (name, len(entries)))
    print("Run in Studio (Edit mode, execute_luau); nothing is installed:")
    print('  return require(game.ServerStorage.Dev.StudioSync:Clone()).check("%s")' % name)


def cmd_confirm(args):
    name = args[0]
    tag = "LSS|%s|" % name
    log = newest_log_with(tag + "done|")
    if not log:
        sys.exit("no result for pack %s in Studio's log yet (did apply run?)" % name)
    results, done = {}, None
    with io.open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            i = line.find(tag)
            if i < 0:
                continue
            f = line[i + len(tag):].rstrip("\r\n").split("|", 4)
            if f[0] == "done":
                done = f
                continue
            status, path, nbytes, h = f[0], f[1], int(f[2]), f[3]
            results[path] = (status, nbytes, h, f[4] if len(f) > 4 else "")
    if done and done[1] == "dry":
        print("dry run only; state not changed")
    with Locked():
        state = load_state()
        bad = []
        for path, (status, nbytes, h, detail) in sorted(results.items()):
            if status in ("updated", "created", "same"):
                if not (done and done[1] == "dry" and status != "same"):
                    state[path] = {"fnv": h, "bytes": nbytes}
            else:
                bad.append((status, path, detail))
        save_state(state)
    counts = {}
    for status, *_ in results.values():
        counts[status] = counts.get(status, 0) + 1
    print("pack %s: %s" % (name, ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items()))))
    for status, path, detail in bad:
        print("  %s  %s  %s" % (status.upper(), path, detail))
    if bad:
        sys.exit(1)


def parse_export(run):
    tag = "LSX|%s|" % run
    log = newest_log_with(tag + "E|")
    if not log:
        sys.exit("no finished export %s in Studio's log" % run)
    heads, chunks, start, end = {}, {}, None, None
    with io.open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            i = line.find(tag)
            if i < 0:
                continue
            msg = line[i + len(tag):].rstrip("\r\n")
            kind = msg[:1]
            if kind == "S":
                start, heads, chunks, end = int(msg.split("|")[1]), {}, {}, None
            elif kind == "B":
                _, idx, path, cls, rc, nbytes, h, n = msg.split("|")
                heads[int(idx)] = dict(path=path, cls=cls, rc=rc or None, bytes=int(nbytes), fnv=h, n=int(n))
            elif kind == "C":
                _, idx, k, data = msg.split("|", 3)
                chunks.setdefault(int(idx), {})[int(k)] = data
            elif kind == "E":
                end = msg
    if start is None or end is None or len(heads) != start:
        sys.exit("export %s is incomplete in the log" % run)
    out = []
    for idx in sorted(heads):
        h = heads[idx]
        got = chunks.get(idx, {})
        if len(got) != h["n"]:
            sys.exit("%s: %d of %d chunks in the log" % (h["path"], len(got), h["n"]))
        data = base64.b64decode("".join(got[k] for k in range(1, h["n"] + 1)))
        if len(data) != h["bytes"] or fnv(data) != h["fnv"]:
            sys.exit("%s: decoded bytes do not match Studio's fingerprint" % h["path"])
        h["data"] = data
        out.append(h)
    return out


def cmd_pull(args):
    write = "--write" in args
    state_only = "--state-only" in args
    run = [a for a in args if not a.startswith("--")][0]
    items = parse_export(run)
    scripts = all_scripts()
    m = load_manifest()
    skipped = [s["path"] for s in m.get("skipped", [])]
    paths = [h["path"] for h in items]
    changed = []
    with Locked():
        state = load_state()
        for h in items:
            sp = h["path"]
            if any(sp == r or sp.startswith(r + ".") for r in skipped):
                continue
            if sp in scripts:
                rel = scripts[sp]["file"]
            else:
                suffix = {"ModuleScript": ".lua", "LocalScript": ".client.lua", "Script": ".server.lua"}[h["cls"]]
                parts = sp.split(".")
                if any(p.startswith(sp + ".") for p in paths):
                    rel = "src/" + "/".join(parts) + "/init" + suffix
                else:
                    rel = "src/" + "/".join(parts) + suffix
            dest = os.path.join(REPO, rel)
            on_disk = read_bytes(dest) if os.path.isfile(lp(dest)) else None
            if on_disk != h["data"]:
                changed.append((sp, rel, None if on_disk is None else len(on_disk), h["bytes"]))
                if write and not state_only:
                    write_bytes(dest, h["data"])
            if write or state_only:
                state[sp] = {"fnv": h["fnv"], "bytes": h["bytes"]}
        if write or state_only:
            save_state(state)
    print("export %s: %d scripts in Studio; %d differ from the repo%s" % (
        run, len(items), len(changed), " (written)" if write and not state_only else ""))
    for sp, rel, was, now in changed:
        print("  %-90s %7s -> %7d" % (sp, "-" if was is None else was, now))


def cmd_blob(args):
    name = args[0]
    entries, blobs = [], []
    for i, spec in enumerate(args[1:], 1):
        key, _, path = spec.partition("=")
        data = read_bytes(path)
        entries.append({"i": i, "kind": "blob", "name": key, "bytes": len(data), "fnv": fnv(data)})
        blobs.append(data)
    path = write_pack(name, entries, blobs)
    print("data pack %s -> %s" % (name, path))
    for e in entries:
        print("  %-30s %10d bytes  %s  (%d chunks)" % (e["name"], e["bytes"], e["fnv"], e["chunks"]))
    print('\nIn Studio: local pack = require(game.ServerStorage.Dev.StudioSync:Clone()).open("%s"); '
          'local b = pack:blob("<name>"); pack:close()' % name)


def cmd_bootstrap(_args):
    data = read_bytes(os.path.join(REPO, "src", "ServerStorage", "Dev", "StudioSync.lua"))
    b64 = base64.b64encode(data).decode("ascii")
    out = [HEADER, '<Item class="Folder" referent="R0"><Properties><string name="Name">LSBoot</string></Properties>',
           '<Item class="StringValue" referent="R1"><Properties><string name="Name">B</string><string name="Value">%s</string>'
           '</Properties></Item>' % b64, "</Item></roblox>"]
    path = os.path.join(studio_dir(), "boot.rbxmx")
    write_bytes(path, "\n".join(out).encode("utf-8"))
    print("boot pack -> %s (%d bytes, fnv %s)" % (path, len(data), fnv(data)))
    print("Run in Studio (Edit):")
    print('  local root = game:GetObjects("rbxasset://ls_import/boot.rbxmx")[1]')
    print('  local src = buffer.tostring(game:GetService("EncodingService"):Base64Decode(buffer.fromstring(root.B.Value)))')
    print('  root:Destroy()')
    print('  local dev = game.ServerStorage.Dev')
    print('  local m = dev:FindFirstChild("StudioSync") or Instance.new("ModuleScript")')
    print('  m.Name = "StudioSync"; m.Source = src; m.Parent = dev')
    print('  return #src')
    with Locked():
        state = load_state()
        state["ServerStorage.Dev.StudioSync"] = {"fnv": fnv(data), "bytes": len(data)}
        save_state(state)


def cmd_clean(_args):
    d = studio_dir()
    n = 0
    for p in glob.glob(os.path.join(d, "p*_*.rbxmx")):
        if time.time() - os.path.getmtime(p) > 6 * 3600:
            os.remove(p)
            n += 1
    print("removed %d old packs from %s" % (n, d))


COMMANDS = {"status": cmd_status, "push": cmd_push, "check": cmd_check, "confirm": cmd_confirm, "pull": cmd_pull,
            "blob": cmd_blob, "bootstrap": cmd_bootstrap, "clean": cmd_clean}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]](sys.argv[2:])
