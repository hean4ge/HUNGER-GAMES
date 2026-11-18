"""mp-test: reads the [MPT] lines out of Studio's log files.
python readlog.py <minutes> [--from N] [--grep text] [--all] [--out file] [--clients]
  <minutes>: only log files written in the last <minutes>
  default: the server's lines (the file with "[MPT] 0001"), from sequence number N on
  --clients: each client's own [MPT][C:..] lines instead (not relayed ones)
"""
import glob, os, re, sys, time
args = sys.argv[1:]
minutes = float(args[0]) if args and not args[0].startswith("--") else 30
def opt(name, default=None):
    if name in args:
        i = args.index(name)
        return args[i + 1] if i + 1 < len(args) and not args[i + 1].startswith("--") else True
    return default
start = int(opt("--from", 0))
pat = opt("--grep")
logs = glob.glob(os.path.join(os.environ["LOCALAPPDATA"], "Roblox", "logs", "*_Studio_*_last.log"))
logs = [p for p in logs if time.time() - os.path.getmtime(p) < minutes * 60]
logs.sort(key=os.path.getctime, reverse=bool(opt("--newest")))
out = []
for p in logs:
    try:
        text = open(p, encoding="utf-8", errors="replace").read()
    except Exception as e:
        continue
    if "[MPT]" not in text:
        continue
    lines = [l for l in text.splitlines() if "[MPT]" in l]
    server = any(re.search(r"\[MPT\] \d{4} ", l) for l in lines)
    if opt("--clients"):
        if server:
            continue
    elif not server:
        continue
    if opt("--newest") and out:
        break
    out.append("=== %s (%d MPT lines, %s)" % (os.path.basename(p), len(lines), "server" if server else "client"))
    for l in lines:
        i = l.index("[MPT]")
        body = l[i:]
        m = re.match(r"\[MPT\] (\d{4}) ", body)
        if m and int(m.group(1)) < start:
            continue
        if pat and pat.lower() not in body.lower():
            continue
        out.append(body)
res = "\n".join(out)
o = opt("--out")
if o:
    open(o, "w", encoding="utf-8").write(res)
    print("wrote %d lines to %s" % (len(out), o))
else:
    sys.stdout.buffer.write(res.encode("utf-8", "replace"))
